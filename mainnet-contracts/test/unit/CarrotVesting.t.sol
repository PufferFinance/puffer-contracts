// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { CarrotVesting } from "../../src/CarrotVesting.sol";
import { CARROT } from "../../src/CARROT.sol";
import { PUFFER } from "../../src/PUFFER.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { InvalidAddress } from "../../src/Errors.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";

contract CarrotVestingTest is Test {
    CarrotVesting public carrotVesting;
    CARROT public carrot;
    PUFFER public puffer;

    uint32 public constant DURATION = 6 * 30 days;
    uint32 public constant STEPS = 6;
    uint256 public constant TOTAL_PUFFER_REWARDS = 55_000_000 ether;
    uint256 public constant MAX_CARROT_AMOUNT = 100_000_000 ether;
    uint256 public constant EXCHANGE_RATE = 1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public dead = address(0xDEAD);

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        carrot = new CARROT(address(this));
        puffer = new PUFFER(address(this));
        carrotVesting = new CarrotVesting(address(carrot), address(puffer), address(this));

        puffer.unpause();
        carrot.transfer(alice, 100_00 ether);
        carrot.transfer(bob, 100_00 ether);

        vm.label(alice, "alice");
        vm.label(bob, "bob");
    }

    modifier initialized() {
        puffer.approve(address(carrotVesting), TOTAL_PUFFER_REWARDS);
        vm.expectEmit(true, true, true, true);
        emit CarrotVesting.Initialized(
            block.timestamp,
            DURATION,
            STEPS
        );
        carrotVesting.initialize(uint48(block.timestamp), DURATION, STEPS);
        _;
    }

    function test_constructor() public {
        assertEq(address(carrotVesting.CARROT()), address(carrot), "CARROT address is not correct");
        assertEq(address(carrotVesting.PUFFER()), address(puffer), "PUFFER address is not correct");
        assertEq(carrotVesting.owner(), address(this), "Owner is not correct");

        vm.expectRevert(InvalidAddress.selector);
        new CarrotVesting(address(0), address(puffer), address(this));
        vm.expectRevert(InvalidAddress.selector);
        new CarrotVesting(address(carrot), address(0), address(this));
    }

    function test_initialize_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        carrotVesting.initialize(uint48(block.timestamp), DURATION, STEPS);
        vm.stopPrank();
    }

    function test_initialize_AlreadyInitialized() public initialized {
        vm.expectRevert(CarrotVesting.AlreadyInitialized.selector);
        carrotVesting.initialize(uint48(block.timestamp), DURATION, STEPS);
    }

    function test_initialize_failed() public {
        vm.expectRevert(CarrotVesting.InvalidStartTimestamp.selector);
        carrotVesting.initialize(uint48(block.timestamp - 1), DURATION, STEPS);
        vm.expectRevert(CarrotVesting.InvalidDuration.selector);
        carrotVesting.initialize(uint48(block.timestamp), 0, STEPS);
        vm.expectRevert(CarrotVesting.InvalidSteps.selector);
        carrotVesting.initialize(uint48(block.timestamp), DURATION, 0);
    }

    function test_initialize() public initialized {
        assertEq(carrotVesting.startTimestamp(), block.timestamp, "Start timestamp is not correct");
        assertEq(carrotVesting.duration(), DURATION, "Duration is not correct");
        assertEq(carrotVesting.steps(), STEPS, "Steps are not correct");
        assertEq(carrotVesting.totalDepositedAmount(), 0, "Total deposited amount is not correct");
        assertEq(
            carrotVesting.EXCHANGE_RATE(),
            1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT,
            "Exchange rate is not correct"
        );
    }

    function test_deposit_NotStarted() public {
        vm.expectRevert(CarrotVesting.NotStarted.selector);
        carrotVesting.deposit(100 ether);
    }

    function test_deposit_AlreadyDeposited() public initialized {
        vm.startPrank(alice);
        carrot.approve(address(carrotVesting), 200 ether);
        carrotVesting.deposit(100 ether);
        vm.expectRevert(CarrotVesting.AlreadyDeposited.selector);
        carrotVesting.deposit(100 ether);
        vm.stopPrank();
    }

    function test_deposit() public initialized {
        uint256 carrotBalanceBefore = carrot.balanceOf(alice);
        uint256 depositAmount = 100 ether;
        _deposit(alice, depositAmount);

        uint256 carrotBalanceAfter = carrot.balanceOf(alice);
        assertEq(carrotBalanceAfter, carrotBalanceBefore - depositAmount, "Carrot balance is not correct");
        assertEq(carrot.balanceOf(dead), depositAmount, "Carrot is not burned");

        _checkVesting(alice, depositAmount, 0, block.timestamp, block.timestamp);
    }

    function test_depositWithPermit_NotStarted() public {
        uint256 depositAmount = 100 ether;

        // Generate a valid permit
        Permit memory permit = _signPermit(
            "alice",
            address(carrotVesting),
            depositAmount,
            block.timestamp + 1000,
            IERC20Permit(address(carrot)).DOMAIN_SEPARATOR()
        );

        vm.startPrank(alice);
        vm.expectRevert(CarrotVesting.NotStarted.selector);
        carrotVesting.depositWithPermit(permit);
        vm.stopPrank();
    }

    function test_depositWithPermit_AlreadyDeposited() public initialized {
        uint256 depositAmount = 100 ether;

        // First deposit with regular deposit function
        vm.startPrank(alice);
        carrot.approve(address(carrotVesting), depositAmount);
        carrotVesting.deposit(depositAmount);
        vm.stopPrank();

        // Try to deposit again with permit
        Permit memory permit = _signPermit(
            "alice",
            address(carrotVesting),
            depositAmount,
            block.timestamp + 1000,
            IERC20Permit(address(carrot)).DOMAIN_SEPARATOR()
        );

        vm.startPrank(alice);
        vm.expectRevert(CarrotVesting.AlreadyDeposited.selector);
        carrotVesting.depositWithPermit(permit);
        vm.stopPrank();
    }

    function test_depositWithPermit() public initialized {
        uint256 carrotBalanceBefore = carrot.balanceOf(alice);
        uint256 depositAmount = 100 ether;

        // Generate a valid permit
        Permit memory permit = _signPermit(
            "alice",
            address(carrotVesting),
            depositAmount,
            block.timestamp + 1000,
            IERC20Permit(address(carrot)).DOMAIN_SEPARATOR()
        );

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit CarrotVesting.Deposited(alice, depositAmount);
        carrotVesting.depositWithPermit(permit);
        vm.stopPrank();

        uint256 carrotBalanceAfter = carrot.balanceOf(alice);
        assertEq(carrotBalanceAfter, carrotBalanceBefore - depositAmount, "Carrot balance is not correct");
        assertEq(carrot.balanceOf(dead), depositAmount, "Carrot is not burned");

        _checkVesting(alice, depositAmount, 0, block.timestamp, block.timestamp);
    }

    function test_claim_NoClaimableAmount() public initialized {
        vm.startPrank(alice);
        vm.expectRevert(CarrotVesting.NoClaimableAmount.selector);
        carrotVesting.claim();

        _deposit(alice, 100 ether);

        vm.expectRevert(CarrotVesting.NoClaimableAmount.selector);
        carrotVesting.claim();
        vm.stopPrank();
    }

    function test_claim() public initialized {
        uint256 initTimestamp = block.timestamp;
        uint256 depositAmount = 100 ether;
        _deposit(alice, depositAmount);

        uint256 stepDuration = DURATION / STEPS;
        uint256 totalExpectedClaimableAmount = EXCHANGE_RATE * depositAmount / 1e18;
        uint256 returnedClaimedAmount;
        uint256 totalClaimedAmount;

        skip(stepDuration - 1); // Go to the future

        vm.startPrank(alice);
        vm.expectRevert(CarrotVesting.NoClaimableAmount.selector);
        carrotVesting.claim();

        skip(1);

        uint256 expectedClaimableAmount = EXCHANGE_RATE * depositAmount / STEPS / 1e18;

        uint256 pufferBalanceBefore = puffer.balanceOf(alice);

        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        totalClaimedAmount += returnedClaimedAmount;
        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertApproxEqAbs(
            pufferBalanceAfter, pufferBalanceBefore + expectedClaimableAmount, 1, "Puffer balance is not correct"
        );

        _checkVesting(alice, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp);

        skip(stepDuration);

        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        totalClaimedAmount += returnedClaimedAmount;

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter2 = puffer.balanceOf(alice);
        assertApproxEqAbs(
            pufferBalanceAfter2, pufferBalanceAfter + expectedClaimableAmount, 1, "Puffer balance is not correct"
        );

        _checkVesting(alice, depositAmount, expectedClaimableAmount * 2, block.timestamp, initTimestamp);

        skip(DURATION);

        expectedClaimableAmount = totalExpectedClaimableAmount - totalClaimedAmount;

        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        totalClaimedAmount += returnedClaimedAmount;

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter3 = puffer.balanceOf(alice);
        assertApproxEqAbs(
            pufferBalanceAfter3, pufferBalanceAfter2 + expectedClaimableAmount, 1, "Puffer balance is not correct"
        );

        _checkVesting(alice, depositAmount, totalExpectedClaimableAmount, block.timestamp, initTimestamp);

        vm.expectRevert(CarrotVesting.NoClaimableAmount.selector);
        carrotVesting.claim();
    }

    function test_claimAllAtOnce() public initialized {
        uint256 depositAmount = 100 ether;
        _deposit(alice, depositAmount);
        uint256 initTimestamp = block.timestamp;

        uint256 pufferBalanceBefore = puffer.balanceOf(alice);
        uint256 expectedClaimableAmount = EXCHANGE_RATE * depositAmount / 1e18;

        skip(2 * DURATION);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        uint256 returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertEq(returnedClaimedAmount, expectedClaimableAmount, "Claimed amount is not correct");

        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertEq(pufferBalanceAfter, pufferBalanceBefore + expectedClaimableAmount, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp);

        skip(2 * DURATION);

        vm.startPrank(alice);
        vm.expectRevert(CarrotVesting.NoClaimableAmount.selector);
        carrotVesting.claim();
        vm.stopPrank();
    }

    function test_claimVestAll() public initialized {
        uint256 depositAmountAlice = MAX_CARROT_AMOUNT / 4;
        uint256 depositAmountBob = 3 * MAX_CARROT_AMOUNT / 4;

        deal(address(carrot), alice, depositAmountAlice);
        deal(address(carrot), bob, depositAmountBob);

        uint256 initTimestamp = block.timestamp;
        uint256 totalExpectedClaimableAmountAlice = EXCHANGE_RATE * depositAmountAlice / 1e18;
        uint256 totalExpectedClaimableAmountBob = EXCHANGE_RATE * depositAmountBob / 1e18;

        _deposit(alice, depositAmountAlice);
        _deposit(bob, depositAmountBob);

        skip(DURATION);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, totalExpectedClaimableAmountAlice);
        uint256 returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertEq(returnedClaimedAmount, totalExpectedClaimableAmountAlice, "Claimed amount is not correct");

        _checkVesting(alice, depositAmountAlice, totalExpectedClaimableAmountAlice, block.timestamp, initTimestamp);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(bob, totalExpectedClaimableAmountBob);
        returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertApproxEqAbs(puffer.balanceOf(address(carrotVesting)), 0, 1, "Puffer balance is not correct");
    }

    function test_claim_fuzzy(
        uint256 duration,
        uint256 steps,
        uint256 depositAmount,
        uint256 waitTime
    ) public {
        duration = bound(duration, 10 days, 365 days);
        steps = bound(steps, 2, 100);
        depositAmount = bound(depositAmount, 1 ether, MAX_CARROT_AMOUNT);
        uint256 stepDuration = duration / steps;
        waitTime = bound(waitTime, stepDuration, duration);

        puffer.approve(address(carrotVesting), TOTAL_PUFFER_REWARDS);
        carrotVesting.initialize(uint48(block.timestamp), uint32(duration), uint32(steps));

        deal(address(carrot), alice, depositAmount);

        _deposit(alice, depositAmount);

        uint256 initTimestamp = block.timestamp;

        skip(waitTime);

        uint256 numStepsPassed = (block.timestamp - initTimestamp) / stepDuration;

        uint256 expectedClaimableAmount = (numStepsPassed * depositAmount / steps) * EXCHANGE_RATE / 1e18;

        vm.startPrank(alice);
        vm.expectEmit(address(carrotVesting));
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        uint256 returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");
        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertApproxEqAbs(pufferBalanceAfter, expectedClaimableAmount, 1, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp);
    }

    function test_claim_fuzzy2(
        uint256 duration,
        uint256 steps,
        uint256 depositAmount,
        uint256 waitTime
    ) public {
        duration = bound(duration, 10 days, 365 days);
        steps = bound(steps, 2, 100);
        depositAmount = bound(depositAmount, 1 ether, MAX_CARROT_AMOUNT);
        uint256 stepDuration = duration / steps;
        waitTime = bound(waitTime, stepDuration, duration - stepDuration);

        uint256 totalExpectedClaimableAmount = EXCHANGE_RATE * depositAmount / 1e18;

        puffer.approve(address(carrotVesting), TOTAL_PUFFER_REWARDS);
        carrotVesting.initialize(uint48(block.timestamp), uint32(duration), uint32(steps));

        deal(address(carrot), alice, depositAmount);

        _deposit(alice, depositAmount);

        uint256 initTimestamp = block.timestamp;

        skip(waitTime);

        uint256 numStepsPassed = (block.timestamp - initTimestamp) / stepDuration;

        uint256 expectedClaimableAmount = (numStepsPassed * depositAmount / steps) * EXCHANGE_RATE / 1e18;

        vm.startPrank(alice);
        vm.expectEmit(address(carrotVesting));
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        uint256 returnedClaimedAmount = carrotVesting.claim();

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertApproxEqAbs(pufferBalanceAfter, expectedClaimableAmount, 1, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp);

        skip(duration);

        expectedClaimableAmount = totalExpectedClaimableAmount - expectedClaimableAmount;

        vm.expectEmit(address(carrotVesting));
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        assertEq(returnedClaimedAmount, expectedClaimableAmount, "Claimed amount is not correct");

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter2 = puffer.balanceOf(alice);
        assertApproxEqAbs(pufferBalanceAfter2, totalExpectedClaimableAmount, 1, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount, totalExpectedClaimableAmount, block.timestamp, initTimestamp);
    }

    function test_dismantle_Unauthorized() public initialized {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        carrotVesting.dismantle();
        vm.stopPrank();
    }

    function test_dismantle_NotEnoughTimePassed() public initialized {
        vm.expectRevert(CarrotVesting.NotEnoughTimePassed.selector);
        carrotVesting.dismantle();
    }

    function test_dismantle() public initialized {
        skip(carrotVesting.MIN_TIME_TO_DISMANTLE_VESTING());
        vm.expectEmit(true, true, true, true);
        emit CarrotVesting.Dismantled(TOTAL_PUFFER_REWARDS);
        carrotVesting.dismantle();
        assertTrue(carrotVesting.isDismantled(), "Vesting is not dismantled");

        vm.startPrank(alice);
        vm.expectRevert(CarrotVesting.AlreadyDismantled.selector);
        carrotVesting.deposit(1 ether);

        vm.expectRevert(CarrotVesting.AlreadyDismantled.selector);
        carrotVesting.claim();
        vm.stopPrank();
    }

    function _deposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        carrot.approve(address(carrotVesting), amount);
        vm.expectEmit(true, true, true, true);
        emit CarrotVesting.Deposited(user, amount);
        carrotVesting.deposit(amount);
        vm.stopPrank();
    }

    function _signPermit(string memory seed, address to, uint256 amount, uint256 deadline, bytes32 domainSeparator)
        internal
        returns (Permit memory p)
    {
        address owner;
        uint256 privateKey;
        (owner, privateKey) = makeAddrAndKey(seed);
        uint256 nonce = IERC20Permit(address(carrot)).nonces(owner);

        bytes32 innerHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, to, amount, nonce, deadline));
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, outerHash);

        return Permit({ deadline: deadline, amount: amount, v: v, r: r, s: s });
    }

    function _checkVesting(
        address user,
        uint256 expectedDepositedAmount,
        uint256 expectedClaimedAmount,
        uint256 expectedLastClaimedTimestamp,
        uint256 expectedDepositedTimestamp
    ) internal view {
        (uint256 depositedAmount, uint256 claimedAmount, uint256 lastClaimedTimestamp, uint256 depositedTimestamp) =
            carrotVesting.vestings(user);
        assertApproxEqAbs(depositedAmount, expectedDepositedAmount, 1, "Deposited amount is not correct");
        assertApproxEqAbs(claimedAmount, expectedClaimedAmount, 1, "Claimed amount is not correct");
        assertApproxEqAbs(
            lastClaimedTimestamp, expectedLastClaimedTimestamp, 1, "Last claimed timestamp is not correct"
        );
        assertApproxEqAbs(depositedTimestamp, expectedDepositedTimestamp, 1, "Deposited timestamp is not correct");
    }
}
