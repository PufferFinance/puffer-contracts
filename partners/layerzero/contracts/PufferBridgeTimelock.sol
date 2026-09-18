// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PufferBridgeTimelock
 * @author Puffer Finance
 * @notice Timelock contract that requires a delay for every transaction except for whitelisted selectors
 *         that can be executed without a delay
 * @dev Whitelisting a selector grants a privilege, so it must itself go through the timelock.
 *      Removing one only revokes a privilege, so the `EXECUTOR` can do it immediately
 * @custom:security-contact security@puffer.fi
 */
contract PufferBridgeTimelock is ReentrancyGuard {
    using Address for address;

    /**
     * @notice Describes whether a transaction may be executed, and why
     * @param NotExecutable The transaction is not queued and its selector is not whitelisted
     * @param Locked The transaction is queued but its delay has not elapsed yet
     * @param Ready The transaction is queued and its delay has elapsed
     * @param Whitelisted The selector is whitelisted on the target, so no delay applies
     */
    enum ExecutionStatus {
        NotExecutable,
        Locked,
        Ready,
        Whitelisted
    }

    /**
     * @notice Error to be thrown when an invalid address is encountered
     */
    error InvalidAddress();
    /**
     * @notice Error to be thrown when an invalid delay is encountered
     */
    error InvalidDelay(uint256 delay);
    /**
     * @notice Error to be thrown when an unauthorized action is attempted
     */
    error Unauthorized();
    /**
     * @notice Error to be thrown when an invalid transaction is attempted
     * @param txHash The keccak256 hash of the invalid transaction
     */
    error InvalidTransaction(bytes32 txHash);

    /**
     * @notice Error to be thrown when a calldata is shorter than 4 bytes
     */
    error InvalidCalldata();
    /**
     * @notice Error to be thrown when a transaction is attempted before the lock period expires
     * @param txHash The keccak256 hash of the locked transaction
     * @param lockedUntil The timestamp when the transaction can be executed
     */
    error Locked(bytes32 txHash, uint256 lockedUntil);

    /**
     * @notice Error to be thrown when removing a selector that is not currently whitelisted
     * @param target The address of the contract that exposes the function selector
     * @param selector The 4 byte function selector that is not whitelisted
     */
    error SelectorNotWhitelisted(address target, bytes4 selector);

    /**
     * @notice Emitted when the delay changes from `oldDelay` to `newDelay`
     * @param oldDelay The previous timelock delay in seconds
     * @param newDelay The new timelock delay in seconds
     */
    event DelayChanged(uint256 oldDelay, uint256 newDelay);
    /**
     * @notice Emitted when a transaction is queued
     * @param txHash The keccak256 hash of the queued transaction
     * @param target The address to which the transaction will be sent
     * @param callData The data to be sent along with the transaction
     * @param operationId The id of the operation used to identify the transaction
     * @param lockedUntil The timestamp when the transaction can be executed
     */
    event TransactionQueued(
        bytes32 indexed txHash, address indexed target, bytes callData, uint256 indexed operationId, uint256 lockedUntil
    );
    /**
     * @notice Emitted when a transaction is canceled
     * @param txHash The keccak256 hash of the canceled transaction
     * @param target The address to which the transaction was to be sent
     * @param operationId The id of the operation used to identify the transaction
     * @param callData The data that was to be sent along with the transaction
     */
    event TransactionCanceled(
        bytes32 indexed txHash, address indexed target, bytes callData, uint256 indexed operationId
    );
    /**
     * @notice Emitted when a transaction is executed
     * @param txHash The keccak256 hash of the executed transaction
     * @param target The address to which the transaction was sent
     * @param operationId The id of the operation used to identify the transaction
     * @param callData The data that was sent along with the transaction
     * @param whitelisted `true` if the selector was whitelisted and the transaction executed with no
     *        delay, `false` if it went through the queue and the delay
     */
    event TransactionExecuted(
        bytes32 indexed txHash, address indexed target, bytes callData, uint256 indexed operationId, bool whitelisted
    );
    /**
     * @notice Emitted when a function selector is added to the whitelist for a target, meaning it
     *         can from then on be executed with no delay
     * @param target The address of the contract that exposes the function selector
     * @param selector The 4 byte function selector that got whitelisted
     */
    event SelectorWhitelisted(address indexed target, bytes4 indexed selector);
    /**
     * @notice Emitted when a function selector is removed from the whitelist for a target, meaning
     *         it must from then on go through the queue and the delay again
     * @param target The address of the contract that exposes the function selector
     * @param selector The 4 byte function selector that got removed from the whitelist
     */
    event SelectorRemovedFromWhitelist(address indexed target, bytes4 indexed selector);

    /**
     * @notice Minimum delay enforced by the contract
     */
    uint256 public constant MINIMUM_DELAY = 1 days;

    /**
     * @notice Maximum delay enforced by the contract
     */
    uint256 public constant MAXIMUM_DELAY = 30 days;

    /**
     * @notice Address that can queue, execute and cancel transactions
     */
    address public immutable EXECUTOR;

    /**
     * @notice Timelock delay in seconds
     */
    uint256 public delay;

    /**
     * @notice Transaction queue
     * @dev Maps the keccak256 hash of a queued transaction to the timestamp from which it may be
     *      executed. A value of `0` means the transaction is not queued
     */
    mapping(bytes32 transactionHash => uint256 lockedUntil) public queue;

    /**
     * @notice Function selectors whitelisted to be executed with no delay on target address
     * @dev Whitelisting is scoped per target: the same selector may be whitelisted on one target
     *      and not on another. It is not scoped by arguments
     */
    mapping(address target => mapping(bytes4 selector => bool whitelisted)) public whitelistedSelectors;

    /**
     * @notice Deploys the timelock
     * @param executor The address allowed to queue, cancel and execute transactions
     * @param initialDelay The initial timelock delay in seconds, must be within
     *        `MINIMUM_DELAY` and `MAXIMUM_DELAY`
     */
    constructor(address executor, uint256 initialDelay) {
        require(executor != address(0), InvalidAddress());
        _setDelay(initialDelay);
        EXECUTOR = executor;
    }

    /**
     * @notice Restricts a function to the `EXECUTOR`
     */
    modifier onlyExecutor() {
        require(msg.sender == EXECUTOR, Unauthorized());
        _;
    }

    /**
     * @notice Restricts a function to the timelock itself, meaning it can only be reached through a
     *         transaction that went through `queueTransaction` and the delay
     */
    modifier onlyTimelock() {
        require(msg.sender == address(this), Unauthorized());
        _;
    }

    /**
     * @notice Executor queues a transaction that can be executed by the Executor after the delay period
     * @param target The address to which the transaction will be sent
     * @param callData The data to be sent along with the transaction
     * @param operationId The id of the operation used to identify the transaction
     * @return The keccak256 hash of the queued transaction
     * @dev Reverts if an identical `(target, callData, operationId)` triple is already queued
     */
    function queueTransaction(address target, bytes calldata callData, uint256 operationId)
        external
        onlyExecutor
        returns (bytes32)
    {
        bytes32 txHash = hashTransaction(target, callData, operationId);
        uint256 lockedUntil = block.timestamp + delay;
        if (queue[txHash] != 0) {
            revert InvalidTransaction(txHash);
        }
        queue[txHash] = lockedUntil;
        // solhint-disable-next-line func-named-parameters
        emit TransactionQueued(txHash, target, callData, operationId, lockedUntil);

        return txHash;
    }

    /**
     * @notice Cancels a queued transaction
     * @param target The address to which the transaction was to be sent
     * @param callData The data that was to be sent along with the transaction
     * @param operationId The id of the operation used to identify the transaction
     */
    function cancelTransaction(address target, bytes calldata callData, uint256 operationId) external onlyExecutor {
        bytes32 txHash = hashTransaction(target, callData, operationId);

        // slither-disable-next-line incorrect-equality
        if (queue[txHash] == 0) {
            revert InvalidTransaction(txHash);
        }

        queue[txHash] = 0;

        emit TransactionCanceled(txHash, target, callData, operationId);
    }

    /**
     * @notice Executes a transaction on `target`
     * @dev If the selector of `callData` is whitelisted for `target` the transaction is executed
     *      immediately and does not need to have been queued. Otherwise the transaction must have
     *      been queued and its delay must have elapsed, and the queue entry is consumed
     * @param target The address to which the transaction will be sent
     * @param callData The data to be sent along with the transaction, must be at least 4 bytes long
     * @param operationId The id of the operation used to identify the transaction.
     *        If selector is whitelisted, operationId is ignored
     * @return returnData The data returned by the transaction
     */
    function executeTransaction(address target, bytes calldata callData, uint256 operationId)
        external
        onlyExecutor
        nonReentrant
        returns (bytes memory returnData)
    {
        (ExecutionStatus status, uint256 lockedUntil, bytes32 txHash) = _executionStatus(target, callData, operationId);

        // Non-whitelisted selectors must follow the queue and delay rules
        // slither-disable-next-line incorrect-equality
        if (status == ExecutionStatus.NotExecutable) {
            revert InvalidTransaction(txHash);
        }
        if (status == ExecutionStatus.Locked) {
            revert Locked(txHash, lockedUntil);
        }

        bool whitelisted = status == ExecutionStatus.Whitelisted;

        // This could be skipped when whitelisted, but it is done unconditionally so that a
        // transaction queued before its selector was whitelisted does not leave a stale entry
        queue[txHash] = 0;

        // Execute the transaction
        // slither-disable-next-line arbitrary-send-eth
        returnData = target.functionCall(callData);

        emit TransactionExecuted(txHash, target, callData, operationId, whitelisted);
    }

    /**
     * @notice Sets a new delay for the timelock
     * @param newDelay The new delay in seconds
     * @dev Only callable by the Timelock itself, so it should be a delayed transaction
     */
    function setDelay(uint256 newDelay) external onlyTimelock {
        _setDelay(newDelay);
    }

    /**
     * @notice Adds a function selector on `target` to the whitelist
     * @dev Only callable by the Timelock itself, so it must go through the delay. Whitelisted
     *      selectors bypass the timelock entirely, so they must be granted with care
     * @param target The address of the contract that exposes the function selector
     * @param selector The 4 byte function selector to whitelist
     */
    function addSelectorToWhitelist(address target, bytes4 selector) external onlyTimelock {
        require(target != address(0) && target != address(this) && target.code.length > 0, InvalidAddress());
        whitelistedSelectors[target][selector] = true;
        emit SelectorWhitelisted(target, selector);
    }

    /**
     * @notice Removes a function selector on `target` from the whitelist
     * @dev Callable directly by the `EXECUTOR` with no delay, so that a selector can be revoked
     *      quickly for security reasons. Revoking only ever removes a privilege, which is why it
     *      does not need to go through the timelock the way `addSelectorToWhitelist` does
     * @param target The address of the contract that exposes the function selector
     * @param selector The 4 byte function selector to remove from the whitelist
     */
    function removeSelectorFromWhitelist(address target, bytes4 selector) external onlyExecutor {
        require(whitelistedSelectors[target][selector], SelectorNotWhitelisted(target, selector));
        whitelistedSelectors[target][selector] = false;
        emit SelectorRemovedFromWhitelist(target, selector);
    }

    /**
     * @notice Reports whether a transaction may be executed right now, and how long is left if not
     * @dev Does not revert when a transaction is simply not executable, so that callers can batch
     *      these checks. It does revert on `callData` shorter than 4 bytes, which can never be a
     *      valid call
     * @param target The address to which the transaction would be sent
     * @param callData The data that would be sent along with the transaction
     * @param operationId The id of the operation used to identify the transaction, ignored when the
     *        selector is whitelisted on `target`
     * @return status The execution status of the transaction
     * @return secondsRemaining Seconds left until the transaction becomes executable, non zero only
     *         when `status` is `Locked`
     * @return txHash The keccak256 hash identifying the transaction in the `queue`
     */
    function getExecutionStatus(address target, bytes calldata callData, uint256 operationId)
        external
        view
        returns (ExecutionStatus status, uint256 secondsRemaining, bytes32 txHash)
    {
        uint256 lockedUntil;
        (status, lockedUntil, txHash) = _executionStatus(target, callData, operationId);

        if (status == ExecutionStatus.Locked) {
            secondsRemaining = lockedUntil - block.timestamp;
        }
    }

    /**
     * @notice Computes the hash that identifies a transaction in the `queue`
     * @dev Exposed so that callers never have to reproduce the preimage off chain
     * @param target The address to which the transaction would be sent
     * @param callData The data that would be sent along with the transaction
     * @param operationId The id of the operation used to identify the transaction
     * @return The keccak256 hash of the transaction
     */
    function hashTransaction(address target, bytes calldata callData, uint256 operationId)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(target, callData, operationId));
    }

    /**
     * @notice Resolves the execution status of a transaction
     * @dev Single source of truth shared by `executeTransaction` and `getExecutionStatus`, so the
     *      view can never disagree with what execution actually does
     * @param target The address to which the transaction would be sent
     * @param callData The data that would be sent along with the transaction
     * @param operationId The id of the operation used to identify the transaction
     * @return status The execution status of the transaction
     * @return lockedUntil The timestamp from which the transaction may be executed, `0` unless the
     *         transaction is queued
     * @return txHash The keccak256 hash identifying the transaction in the `queue`
     */
    function _executionStatus(address target, bytes calldata callData, uint256 operationId)
        internal
        view
        returns (ExecutionStatus status, uint256 lockedUntil, bytes32 txHash)
    {
        require(callData.length >= 4, InvalidCalldata());

        txHash = hashTransaction(target, callData, operationId);

        if (whitelistedSelectors[target][bytes4(callData[:4])]) {
            return (ExecutionStatus.Whitelisted, 0, txHash);
        }

        lockedUntil = queue[txHash];

        // slither-disable-next-line incorrect-equality
        if (lockedUntil == 0) {
            return (ExecutionStatus.NotExecutable, 0, txHash);
        }

        status = block.timestamp < lockedUntil ? ExecutionStatus.Locked : ExecutionStatus.Ready;
    }

    /**
     * @notice Sets the timelock delay
     * @dev Reverts unless `MINIMUM_DELAY <= newDelay <= MAXIMUM_DELAY`
     * @param newDelay The new delay in seconds
     */
    function _setDelay(uint256 newDelay) internal {
        require(newDelay >= MINIMUM_DELAY && newDelay <= MAXIMUM_DELAY, InvalidDelay(newDelay));
        emit DelayChanged(delay, newDelay);
        delay = newDelay;
    }
}
