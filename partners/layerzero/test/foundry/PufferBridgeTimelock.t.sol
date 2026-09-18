// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PufferBridgeTimelock} from "../../contracts/PufferBridgeTimelock.sol";

/**
 * @notice Minimal call target used to assert that the timelock forwards calldata and return data
 */
contract TargetMock {
    uint256 public value;

    error Boom();

    function setValue(uint256 newValue) external returns (uint256) {
        value = newValue;
        return newValue * 2;
    }

    function ping() external pure returns (string memory) {
        return "pong";
    }

    function boom() external pure {
        revert Boom();
    }
}

/**
 * @notice Target that calls back into the timelock while the timelock is mid execution
 */
contract ReentrantMock {
    PufferBridgeTimelock public immutable TIMELOCK;

    constructor(PufferBridgeTimelock timelock) {
        TIMELOCK = timelock;
    }

    function reenter() external returns (bytes memory) {
        return TIMELOCK.executeTransaction(address(this), abi.encodeCall(ReentrantMock.reenter, ()), 0);
    }
}

contract PufferBridgeTimelockTest is Test {
    PufferBridgeTimelock public timelock;
    TargetMock public target;

    address public executor = makeAddr("executor");
    address public attacker = makeAddr("attacker");

    uint256 public constant INITIAL_DELAY = 7 days;

    event DelayChanged(uint256 oldDelay, uint256 newDelay);
    event TransactionQueued(
        bytes32 indexed txHash, address indexed target, bytes callData, uint256 indexed operationId, uint256 lockedUntil
    );
    event TransactionCanceled(
        bytes32 indexed txHash, address indexed target, bytes callData, uint256 indexed operationId
    );
    event TransactionExecuted(
        bytes32 indexed txHash, address indexed target, bytes callData, uint256 indexed operationId, bool whitelisted
    );
    event SelectorWhitelisted(address indexed target, bytes4 indexed selector);
    event SelectorRemovedFromWhitelist(address indexed target, bytes4 indexed selector);

    function setUp() public {
        // Move off of timestamp 0 so that `lockedUntil` values are never ambiguous with "not queued"
        vm.warp(1_700_000_000);

        timelock = new PufferBridgeTimelock(executor, INITIAL_DELAY);
        target = new TargetMock();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Runs a full queue + wait + execute cycle as the executor
     */
    function _queueAndExecute(address to, bytes memory callData, uint256 operationId) internal returns (bytes memory) {
        vm.prank(executor);
        timelock.queueTransaction(to, callData, operationId);

        vm.warp(block.timestamp + timelock.delay());

        vm.prank(executor);
        return timelock.executeTransaction(to, callData, operationId);
    }

    /**
     * @notice Whitelists a selector by driving it through the timelock, the only way it can be added
     */
    function _whitelist(address to, bytes4 selector) internal {
        _queueAndExecute(
            address(timelock),
            abi.encodeCall(PufferBridgeTimelock.addSelectorToWhitelist, (to, selector)),
            uint256(keccak256(abi.encode(to, selector)))
        );
    }

    function _status(address to, bytes memory callData, uint256 operationId)
        internal
        view
        returns (PufferBridgeTimelock.ExecutionStatus status, uint256 secondsRemaining, bytes32 txHash)
    {
        return timelock.getExecutionStatus(to, callData, operationId);
    }

    function _assertStatus(PufferBridgeTimelock.ExecutionStatus actual, PufferBridgeTimelock.ExecutionStatus expected)
        internal
        pure
    {
        assertEq(uint8(actual), uint8(expected), "unexpected execution status");
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    function test_constructor() public view {
        assertEq(timelock.EXECUTOR(), executor, "executor");
        assertEq(timelock.delay(), INITIAL_DELAY, "delay");
        assertEq(timelock.MINIMUM_DELAY(), 1 days, "minimum delay");
        assertEq(timelock.MAXIMUM_DELAY(), 30 days, "maximum delay");
    }

    function test_constructor_revertsOnZeroExecutor() public {
        vm.expectRevert(PufferBridgeTimelock.InvalidAddress.selector);
        new PufferBridgeTimelock(address(0), INITIAL_DELAY);
    }

    function test_constructor_revertsBelowMinimumDelay() public {
        uint256 badDelay = 1 days - 1;
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidDelay.selector, badDelay));
        new PufferBridgeTimelock(executor, badDelay);
    }

    function test_constructor_revertsAboveMaximumDelay() public {
        uint256 badDelay = 30 days + 1;
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidDelay.selector, badDelay));
        new PufferBridgeTimelock(executor, badDelay);
    }

    function testFuzz_constructor_acceptsDelayInRange(uint256 delay) public {
        delay = bound(delay, 1 days, 30 days);
        PufferBridgeTimelock fresh = new PufferBridgeTimelock(executor, delay);
        assertEq(fresh.delay(), delay, "delay in range");
    }

    // -------------------------------------------------------------------------
    // Access control
    // -------------------------------------------------------------------------

    function test_queueTransaction_onlyExecutor() public {
        vm.prank(attacker);
        vm.expectRevert(PufferBridgeTimelock.Unauthorized.selector);
        timelock.queueTransaction(address(target), abi.encodeCall(TargetMock.ping, ()), 1);
    }

    function test_cancelTransaction_onlyExecutor() public {
        vm.prank(attacker);
        vm.expectRevert(PufferBridgeTimelock.Unauthorized.selector);
        timelock.cancelTransaction(address(target), abi.encodeCall(TargetMock.ping, ()), 1);
    }

    function test_executeTransaction_onlyExecutor() public {
        vm.prank(attacker);
        vm.expectRevert(PufferBridgeTimelock.Unauthorized.selector);
        timelock.executeTransaction(address(target), abi.encodeCall(TargetMock.ping, ()), 1);
    }

    function test_setDelay_onlyTimelock() public {
        vm.prank(executor);
        vm.expectRevert(PufferBridgeTimelock.Unauthorized.selector);
        timelock.setDelay(2 days);
    }

    function test_addSelectorToWhitelist_onlyTimelock() public {
        vm.prank(executor);
        vm.expectRevert(PufferBridgeTimelock.Unauthorized.selector);
        timelock.addSelectorToWhitelist(address(target), TargetMock.ping.selector);
    }

    function test_removeSelectorFromWhitelist_onlyExecutor() public {
        _whitelist(address(target), TargetMock.setValue.selector);

        vm.prank(attacker);
        vm.expectRevert(PufferBridgeTimelock.Unauthorized.selector);
        timelock.removeSelectorFromWhitelist(address(target), TargetMock.setValue.selector);
    }

    /**
     * @notice Removal is an `EXECUTOR` action, so the timelock itself must not be able to call it
     */
    function test_removeSelectorFromWhitelist_rejectsTimelock() public {
        _whitelist(address(target), TargetMock.setValue.selector);

        vm.prank(address(timelock));
        vm.expectRevert(PufferBridgeTimelock.Unauthorized.selector);
        timelock.removeSelectorFromWhitelist(address(target), TargetMock.setValue.selector);
    }

    // -------------------------------------------------------------------------
    // queueTransaction
    // -------------------------------------------------------------------------

    function test_queueTransaction() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));
        bytes32 expectedHash = timelock.hashTransaction(address(target), callData, 1);
        uint256 expectedLockedUntil = block.timestamp + INITIAL_DELAY;

        vm.expectEmit(true, true, true, true);
        emit TransactionQueued(expectedHash, address(target), callData, 1, expectedLockedUntil);

        vm.prank(executor);
        bytes32 txHash = timelock.queueTransaction(address(target), callData, 1);

        assertEq(txHash, expectedHash, "returned hash");
        assertEq(timelock.queue(txHash), expectedLockedUntil, "locked until");
    }

    function test_queueTransaction_revertsOnDuplicate() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));

        vm.startPrank(executor);
        bytes32 txHash = timelock.queueTransaction(address(target), callData, 1);

        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidTransaction.selector, txHash));
        timelock.queueTransaction(address(target), callData, 1);
        vm.stopPrank();
    }

    function test_queueTransaction_differentOperationIdIsDistinct() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));

        vm.startPrank(executor);
        bytes32 first = timelock.queueTransaction(address(target), callData, 1);
        bytes32 second = timelock.queueTransaction(address(target), callData, 2);
        vm.stopPrank();

        assertTrue(first != second, "operationId must change the hash");
        assertTrue(timelock.queue(first) != 0 && timelock.queue(second) != 0, "both queued");
    }

    // -------------------------------------------------------------------------
    // cancelTransaction
    // -------------------------------------------------------------------------

    function test_cancelTransaction() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));

        vm.startPrank(executor);
        bytes32 txHash = timelock.queueTransaction(address(target), callData, 1);

        vm.expectEmit(true, true, true, true);
        emit TransactionCanceled(txHash, address(target), callData, 1);
        timelock.cancelTransaction(address(target), callData, 1);
        vm.stopPrank();

        assertEq(timelock.queue(txHash), 0, "queue cleared");
    }

    function test_cancelTransaction_revertsWhenNotQueued() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));
        bytes32 txHash = timelock.hashTransaction(address(target), callData, 1);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidTransaction.selector, txHash));
        timelock.cancelTransaction(address(target), callData, 1);
    }

    function test_cancelTransaction_blocksExecution() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));
        bytes32 txHash = timelock.hashTransaction(address(target), callData, 1);

        vm.startPrank(executor);
        timelock.queueTransaction(address(target), callData, 1);
        timelock.cancelTransaction(address(target), callData, 1);

        vm.warp(block.timestamp + INITIAL_DELAY);

        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidTransaction.selector, txHash));
        timelock.executeTransaction(address(target), callData, 1);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // executeTransaction, queued path
    // -------------------------------------------------------------------------

    function test_executeTransaction() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));
        bytes32 txHash = timelock.hashTransaction(address(target), callData, 1);

        vm.prank(executor);
        timelock.queueTransaction(address(target), callData, 1);
        vm.warp(block.timestamp + INITIAL_DELAY);

        vm.expectEmit(true, true, true, true);
        emit TransactionExecuted(txHash, address(target), callData, 1, false);

        vm.prank(executor);
        bytes memory returnData = timelock.executeTransaction(address(target), callData, 1);

        assertEq(abi.decode(returnData, (uint256)), 84, "return data forwarded");
        assertEq(target.value(), 42, "call executed");
        assertEq(timelock.queue(txHash), 0, "queue entry consumed");
    }

    function test_executeTransaction_revertsWhenNotQueued() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));
        bytes32 txHash = timelock.hashTransaction(address(target), callData, 1);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidTransaction.selector, txHash));
        timelock.executeTransaction(address(target), callData, 1);
    }

    function test_executeTransaction_revertsBeforeDelayElapsed() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));
        bytes32 txHash = timelock.hashTransaction(address(target), callData, 1);
        uint256 lockedUntil = block.timestamp + INITIAL_DELAY;

        vm.startPrank(executor);
        timelock.queueTransaction(address(target), callData, 1);

        // One second short of the deadline
        vm.warp(lockedUntil - 1);
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.Locked.selector, txHash, lockedUntil));
        timelock.executeTransaction(address(target), callData, 1);
        vm.stopPrank();
    }

    function test_executeTransaction_succeedsExactlyAtDeadline() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));
        uint256 lockedUntil = block.timestamp + INITIAL_DELAY;

        vm.startPrank(executor);
        timelock.queueTransaction(address(target), callData, 1);
        vm.warp(lockedUntil);
        timelock.executeTransaction(address(target), callData, 1);
        vm.stopPrank();

        assertEq(target.value(), 42, "executable at exactly lockedUntil");
    }

    function test_executeTransaction_cannotReplay() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));
        bytes32 txHash = timelock.hashTransaction(address(target), callData, 1);

        _queueAndExecute(address(target), callData, 1);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidTransaction.selector, txHash));
        timelock.executeTransaction(address(target), callData, 1);
    }

    function test_executeTransaction_revertsOnShortCalldata() public {
        vm.prank(executor);
        vm.expectRevert(PufferBridgeTimelock.InvalidCalldata.selector);
        timelock.executeTransaction(address(target), hex"aabb", 1);
    }

    function test_executeTransaction_bubblesUpTargetRevert() public {
        bytes memory callData = abi.encodeCall(TargetMock.boom, ());

        vm.prank(executor);
        timelock.queueTransaction(address(target), callData, 1);
        vm.warp(block.timestamp + INITIAL_DELAY);

        vm.prank(executor);
        vm.expectRevert(TargetMock.Boom.selector);
        timelock.executeTransaction(address(target), callData, 1);
    }

    function test_executeTransaction_revertsOnCodelessTarget() public {
        address codeless = makeAddr("codeless");
        bytes memory callData = abi.encodeCall(TargetMock.ping, ());

        vm.prank(executor);
        timelock.queueTransaction(codeless, callData, 1);
        vm.warp(block.timestamp + INITIAL_DELAY);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(Address.AddressEmptyCode.selector, codeless));
        timelock.executeTransaction(codeless, callData, 1);
    }

    // -------------------------------------------------------------------------
    // Whitelisted selectors
    // -------------------------------------------------------------------------

    function test_addSelectorToWhitelist() public {
        bytes4 selector = TargetMock.ping.selector;
        bytes memory callData = abi.encodeCall(PufferBridgeTimelock.addSelectorToWhitelist, (address(target), selector));

        vm.prank(executor);
        timelock.queueTransaction(address(timelock), callData, 1);
        vm.warp(block.timestamp + INITIAL_DELAY);

        vm.expectEmit(true, true, true, true);
        emit SelectorWhitelisted(address(target), selector);

        vm.prank(executor);
        timelock.executeTransaction(address(timelock), callData, 1);

        assertTrue(timelock.whitelistedSelectors(address(target), selector), "selector whitelisted");
    }

    function test_addSelectorToWhitelist_revertsOnZeroAddress() public {
        vm.prank(address(timelock));
        vm.expectRevert(PufferBridgeTimelock.InvalidAddress.selector);
        timelock.addSelectorToWhitelist(address(0), TargetMock.ping.selector);
    }

    function test_addSelectorToWhitelist_revertsOnTimelockItself() public {
        vm.prank(address(timelock));
        vm.expectRevert(PufferBridgeTimelock.InvalidAddress.selector);
        timelock.addSelectorToWhitelist(address(timelock), PufferBridgeTimelock.setDelay.selector);
    }

    function test_addSelectorToWhitelist_revertsOnCodelessTarget() public {
        vm.prank(address(timelock));
        vm.expectRevert(PufferBridgeTimelock.InvalidAddress.selector);
        timelock.addSelectorToWhitelist(makeAddr("eoa"), TargetMock.ping.selector);
    }

    function test_whitelistedSelector_executesWithNoDelay() public {
        bytes4 selector = TargetMock.setValue.selector;
        _whitelist(address(target), selector);

        bytes memory callData = abi.encodeCall(TargetMock.setValue, (7));
        bytes32 txHash = timelock.hashTransaction(address(target), callData, 99);

        vm.expectEmit(true, true, true, true);
        emit TransactionExecuted(txHash, address(target), callData, 99, true);

        // Never queued, executed immediately in the same block
        vm.prank(executor);
        timelock.executeTransaction(address(target), callData, 99);

        assertEq(target.value(), 7, "executed with no delay");
    }

    function test_whitelistedSelector_isRepeatable() public {
        _whitelist(address(target), TargetMock.setValue.selector);

        vm.startPrank(executor);
        timelock.executeTransaction(address(target), abi.encodeCall(TargetMock.setValue, (1)), 0);
        timelock.executeTransaction(address(target), abi.encodeCall(TargetMock.setValue, (2)), 0);
        vm.stopPrank();

        assertEq(target.value(), 2, "whitelisted calls are not single use");
    }

    function test_whitelistedSelector_isScopedPerTarget() public {
        TargetMock other = new TargetMock();
        _whitelist(address(target), TargetMock.setValue.selector);

        bytes memory callData = abi.encodeCall(TargetMock.setValue, (1));
        bytes32 txHash = timelock.hashTransaction(address(other), callData, 0);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidTransaction.selector, txHash));
        timelock.executeTransaction(address(other), callData, 0);
    }

    /**
     * @notice Revoking is immediate: no queueing, no delay, and the selector stops bypassing the
     *         timelock in the very same block
     */
    function test_removeSelectorFromWhitelist() public {
        bytes4 selector = TargetMock.setValue.selector;
        _whitelist(address(target), selector);

        uint256 timestampBefore = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit SelectorRemovedFromWhitelist(address(target), selector);

        vm.prank(executor);
        timelock.removeSelectorFromWhitelist(address(target), selector);

        assertEq(block.timestamp, timestampBefore, "removal must not need any delay");
        assertFalse(timelock.whitelistedSelectors(address(target), selector), "revoked");

        bytes memory callData = abi.encodeCall(TargetMock.setValue, (1));
        bytes32 txHash = timelock.hashTransaction(address(target), callData, 0);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidTransaction.selector, txHash));
        timelock.executeTransaction(address(target), callData, 0);
    }

    function test_removeSelectorFromWhitelist_revertsWhenNotWhitelisted() public {
        bytes4 selector = TargetMock.setValue.selector;

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(PufferBridgeTimelock.SelectorNotWhitelisted.selector, address(target), selector)
        );
        timelock.removeSelectorFromWhitelist(address(target), selector);
    }

    function test_removeSelectorFromWhitelist_isNotIdempotent() public {
        bytes4 selector = TargetMock.setValue.selector;
        _whitelist(address(target), selector);

        vm.startPrank(executor);
        timelock.removeSelectorFromWhitelist(address(target), selector);

        vm.expectRevert(
            abi.encodeWithSelector(PufferBridgeTimelock.SelectorNotWhitelisted.selector, address(target), selector)
        );
        timelock.removeSelectorFromWhitelist(address(target), selector);
        vm.stopPrank();
    }

    function test_removeSelectorFromWhitelist_isScopedPerTarget() public {
        TargetMock other = new TargetMock();
        bytes4 selector = TargetMock.setValue.selector;

        _whitelist(address(target), selector);
        _whitelist(address(other), selector);

        vm.prank(executor);
        timelock.removeSelectorFromWhitelist(address(target), selector);

        assertFalse(timelock.whitelistedSelectors(address(target), selector), "removed on target");
        assertTrue(timelock.whitelistedSelectors(address(other), selector), "untouched on other target");
    }

    /**
     * @notice A selector can be re-added after removal, but only through the timelock again
     */
    function test_removedSelectorCanBeReAddedThroughTimelock() public {
        bytes4 selector = TargetMock.setValue.selector;
        _whitelist(address(target), selector);

        vm.prank(executor);
        timelock.removeSelectorFromWhitelist(address(target), selector);

        _whitelist(address(target), selector);
        assertTrue(timelock.whitelistedSelectors(address(target), selector), "re-added");
    }

    /**
     * @notice Revoking mid flight must not strand a transaction: it falls back to the queued path
     */
    function test_removeSelectorFromWhitelist_fallsBackToQueuedPath() public {
        bytes4 selector = TargetMock.setValue.selector;
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (3));

        _whitelist(address(target), selector);

        vm.startPrank(executor);
        timelock.queueTransaction(address(target), callData, 1);
        timelock.removeSelectorFromWhitelist(address(target), selector);
        vm.stopPrank();

        (PufferBridgeTimelock.ExecutionStatus status,,) = _status(address(target), callData, 1);
        _assertStatus(status, PufferBridgeTimelock.ExecutionStatus.Locked);

        vm.warp(block.timestamp + INITIAL_DELAY);
        vm.prank(executor);
        timelock.executeTransaction(address(target), callData, 1);

        assertEq(target.value(), 3, "still executable through the queue");
    }

    /**
     * @notice Regression test for the stale queue entry: a transaction queued before its selector
     *         was whitelisted must still have its queue slot cleared on execution
     */
    function test_queuedThenWhitelisted_clearsQueueEntry() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (5));
        bytes32 txHash = timelock.hashTransaction(address(target), callData, 1);

        vm.prank(executor);
        timelock.queueTransaction(address(target), callData, 1);

        _whitelist(address(target), TargetMock.setValue.selector);

        vm.prank(executor);
        timelock.executeTransaction(address(target), callData, 1);

        assertEq(timelock.queue(txHash), 0, "stale queue entry must be cleared");

        // The same triple can be queued again, which is impossible if the entry leaked
        vm.prank(executor);
        timelock.queueTransaction(address(target), callData, 1);
        assertTrue(timelock.queue(txHash) != 0, "re-queueable");
    }

    // -------------------------------------------------------------------------
    // Self governance, the timelock calling into itself
    // -------------------------------------------------------------------------

    /**
     * @notice `setDelay` is only reachable through `executeTransaction` calling back into
     *         `address(this)`, which happens inside a `nonReentrant` frame. This pins down that the
     *         guard does not block the timelock's own governance path
     */
    function test_setDelay_throughTimelock() public {
        uint256 newDelay = 3 days;
        bytes memory callData = abi.encodeCall(PufferBridgeTimelock.setDelay, (newDelay));

        vm.prank(executor);
        timelock.queueTransaction(address(timelock), callData, 1);
        vm.warp(block.timestamp + INITIAL_DELAY);

        vm.expectEmit(true, true, true, true);
        emit DelayChanged(INITIAL_DELAY, newDelay);

        vm.prank(executor);
        timelock.executeTransaction(address(timelock), callData, 1);

        assertEq(timelock.delay(), newDelay, "delay updated");
    }

    function test_setDelay_appliesToSubsequentQueues() public {
        _queueAndExecute(address(timelock), abi.encodeCall(PufferBridgeTimelock.setDelay, (2 days)), 1);

        bytes memory callData = abi.encodeCall(TargetMock.setValue, (1));
        vm.prank(executor);
        bytes32 txHash = timelock.queueTransaction(address(target), callData, 2);

        assertEq(timelock.queue(txHash), block.timestamp + 2 days, "new delay applied");
    }

    function test_setDelay_revertsBelowMinimum() public {
        bytes memory callData = abi.encodeCall(PufferBridgeTimelock.setDelay, (1 days - 1));

        vm.prank(executor);
        timelock.queueTransaction(address(timelock), callData, 1);
        vm.warp(block.timestamp + INITIAL_DELAY);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidDelay.selector, 1 days - 1));
        timelock.executeTransaction(address(timelock), callData, 1);
    }

    function test_setDelay_revertsAboveMaximum() public {
        bytes memory callData = abi.encodeCall(PufferBridgeTimelock.setDelay, (30 days + 1));

        vm.prank(executor);
        timelock.queueTransaction(address(timelock), callData, 1);
        vm.warp(block.timestamp + INITIAL_DELAY);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PufferBridgeTimelock.InvalidDelay.selector, 30 days + 1));
        timelock.executeTransaction(address(timelock), callData, 1);
    }

    /**
     * @notice A target that calls back into the timelock is not the executor, so it is stopped by
     *         the authorization check before it can reach the reentrancy guard
     */
    function test_reentrantTargetIsRejected() public {
        ReentrantMock reentrant = new ReentrantMock(timelock);
        bytes memory callData = abi.encodeCall(ReentrantMock.reenter, ());

        vm.prank(executor);
        timelock.queueTransaction(address(reentrant), callData, 1);
        vm.warp(block.timestamp + INITIAL_DELAY);

        vm.prank(executor);
        vm.expectRevert(PufferBridgeTimelock.Unauthorized.selector);
        timelock.executeTransaction(address(reentrant), callData, 1);
    }

    // -------------------------------------------------------------------------
    // getExecutionStatus and hashTransaction
    // -------------------------------------------------------------------------

    function test_hashTransaction_matchesPreimage() public view {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));
        assertEq(
            timelock.hashTransaction(address(target), callData, 1),
            keccak256(abi.encode(address(target), callData, uint256(1))),
            "hash preimage"
        );
    }

    function test_getExecutionStatus_notExecutable() public view {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));

        (PufferBridgeTimelock.ExecutionStatus status, uint256 secondsRemaining, bytes32 txHash) =
            _status(address(target), callData, 1);

        _assertStatus(status, PufferBridgeTimelock.ExecutionStatus.NotExecutable);
        assertEq(secondsRemaining, 0, "no countdown");
        assertEq(txHash, timelock.hashTransaction(address(target), callData, 1), "hash");
    }

    function test_getExecutionStatus_locked() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));

        vm.prank(executor);
        timelock.queueTransaction(address(target), callData, 1);

        vm.warp(block.timestamp + 1 days);

        (PufferBridgeTimelock.ExecutionStatus status, uint256 secondsRemaining,) = _status(address(target), callData, 1);

        _assertStatus(status, PufferBridgeTimelock.ExecutionStatus.Locked);
        assertEq(secondsRemaining, INITIAL_DELAY - 1 days, "countdown");
    }

    function test_getExecutionStatus_ready() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));

        vm.prank(executor);
        timelock.queueTransaction(address(target), callData, 1);
        vm.warp(block.timestamp + INITIAL_DELAY);

        (PufferBridgeTimelock.ExecutionStatus status, uint256 secondsRemaining,) = _status(address(target), callData, 1);

        _assertStatus(status, PufferBridgeTimelock.ExecutionStatus.Ready);
        assertEq(secondsRemaining, 0, "no countdown when ready");
    }

    function test_getExecutionStatus_whitelisted() public {
        _whitelist(address(target), TargetMock.setValue.selector);
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));

        (PufferBridgeTimelock.ExecutionStatus status, uint256 secondsRemaining,) = _status(address(target), callData, 1);

        _assertStatus(status, PufferBridgeTimelock.ExecutionStatus.Whitelisted);
        assertEq(secondsRemaining, 0, "no countdown when whitelisted");
    }

    /**
     * @notice A whitelisted selector reports `Whitelisted` even when the same transaction is also
     *         sitting in the queue, because the whitelist takes precedence in execution
     */
    function test_getExecutionStatus_whitelistTakesPrecedenceOverQueue() public {
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));

        vm.prank(executor);
        timelock.queueTransaction(address(target), callData, 1);
        _whitelist(address(target), TargetMock.setValue.selector);

        (PufferBridgeTimelock.ExecutionStatus status, uint256 secondsRemaining,) = _status(address(target), callData, 1);

        _assertStatus(status, PufferBridgeTimelock.ExecutionStatus.Whitelisted);
        assertEq(secondsRemaining, 0, "no countdown");
    }

    function test_getExecutionStatus_revertsOnShortCalldata() public {
        vm.expectRevert(PufferBridgeTimelock.InvalidCalldata.selector);
        timelock.getExecutionStatus(address(target), hex"aabb", 1);
    }

    /**
     * @notice The view must never disagree with execution: `Ready` and `Whitelisted` execute, and
     *         everything else reverts
     */
    function testFuzz_getExecutionStatus_agreesWithExecution(uint256 warpBy, bool queueIt, bool whitelistIt) public {
        warpBy = bound(warpBy, 0, 2 * INITIAL_DELAY);
        bytes memory callData = abi.encodeCall(TargetMock.setValue, (42));

        if (queueIt) {
            vm.prank(executor);
            timelock.queueTransaction(address(target), callData, 1);
        }
        if (whitelistIt) {
            _whitelist(address(target), TargetMock.setValue.selector);
        }

        vm.warp(block.timestamp + warpBy);

        (PufferBridgeTimelock.ExecutionStatus status,,) = _status(address(target), callData, 1);
        bool expectSuccess = status == PufferBridgeTimelock.ExecutionStatus.Ready
            || status == PufferBridgeTimelock.ExecutionStatus.Whitelisted;

        vm.prank(executor);
        try timelock.executeTransaction(address(target), callData, 1) {
            assertTrue(expectSuccess, "executed but status said it should not");
        } catch {
            assertFalse(expectSuccess, "reverted but status said it was executable");
        }
    }

    function testFuzz_hashTransaction_isInjective(address targetA, address targetB, uint256 idA, uint256 idB)
        public
        view
    {
        vm.assume(targetA != targetB || idA != idB);
        bytes memory callData = abi.encodeCall(TargetMock.ping, ());

        assertTrue(
            timelock.hashTransaction(targetA, callData, idA) != timelock.hashTransaction(targetB, callData, idB),
            "distinct inputs must hash differently"
        );
    }
}
