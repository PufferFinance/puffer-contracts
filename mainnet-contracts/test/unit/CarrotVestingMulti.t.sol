// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { CarrotVestingMulti } from "../../src/CarrotVestingMulti.sol";
import { CARROT } from "../../src/CARROT.sol";
import { PUFFER } from "../../src/PUFFER.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";

contract CarrotVestingTest is Test {
    CarrotVestingMulti public carrotVesting;
    CARROT public carrot;
    PUFFER public puffer;

    uint256 public constant DURATION = 6 * 30 days;
    uint256 public constant STEPS = 6;
    uint256 public constant MAX_CARROT_AMOUNT = 100_000_000 ether; // This is the total supply of CARROT which is 100M
    uint256 public constant TOTAL_PUFFER_REWARDS = 55_000_000 ether;
    uint256 public constant EXCHANGE_RATE = 1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public dead = address(0xDEAD);

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        carrot = new CARROT(address(this));
        puffer = new PUFFER(address(this));
        carrotVesting = new CarrotVestingMulti(address(carrot), address(puffer), address(this));

        puffer.unpause();
        carrot.transfer(alice, 100_00 ether);
        carrot.transfer(bob, 100_00 ether);

        vm.label(alice, "alice");
        vm.label(bob, "bob");
    }

    modifier initialized() {
        puffer.approve(address(carrotVesting), TOTAL_PUFFER_REWARDS);
        vm.expectEmit(true, true, true, true);
        emit CarrotVestingMulti.Initialized(
            block.timestamp,
            DURATION,
            STEPS,
            MAX_CARROT_AMOUNT,
            TOTAL_PUFFER_REWARDS,
            1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT
        );
        carrotVesting.initialize(block.timestamp, DURATION, STEPS, MAX_CARROT_AMOUNT, TOTAL_PUFFER_REWARDS);
        _;
    }

    function test_constructor() public view {
        assertEq(address(carrotVesting.CARROT()), address(carrot), "CARROT address is not correct");
        assertEq(address(carrotVesting.PUFFER()), address(puffer), "PUFFER address is not correct");
        assertEq(carrotVesting.owner(), address(this), "Owner is not correct");
    }

    function test_initialize_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        carrotVesting.initialize(block.timestamp, DURATION, STEPS, MAX_CARROT_AMOUNT, TOTAL_PUFFER_REWARDS);
        vm.stopPrank();
    }

    function test_initialize_AlreadyInitialized() public initialized {
        vm.expectRevert(CarrotVestingMulti.AlreadyInitialized.selector);
        carrotVesting.initialize(block.timestamp, DURATION, STEPS, MAX_CARROT_AMOUNT, TOTAL_PUFFER_REWARDS);
    }

    function test_initialize_failed() public {
        vm.expectRevert(CarrotVestingMulti.InvalidStartTimestamp.selector);
        carrotVesting.initialize(block.timestamp - 1, DURATION, STEPS, MAX_CARROT_AMOUNT, TOTAL_PUFFER_REWARDS);
        vm.expectRevert(CarrotVestingMulti.InvalidDuration.selector);
        carrotVesting.initialize(block.timestamp, 0, STEPS, MAX_CARROT_AMOUNT, TOTAL_PUFFER_REWARDS);
        vm.expectRevert(CarrotVestingMulti.InvalidSteps.selector);
        carrotVesting.initialize(block.timestamp, DURATION, 0, MAX_CARROT_AMOUNT, TOTAL_PUFFER_REWARDS);
        vm.expectRevert(CarrotVestingMulti.InvalidMaxCarrotAmount.selector);
        carrotVesting.initialize(block.timestamp, DURATION, STEPS, 0, TOTAL_PUFFER_REWARDS);
        vm.expectRevert(CarrotVestingMulti.InvalidTotalPufferRewards.selector);
        carrotVesting.initialize(block.timestamp, DURATION, STEPS, MAX_CARROT_AMOUNT, 0);
    }

    function test_initialize() public initialized {
        assertEq(carrotVesting.startTimestamp(), block.timestamp, "Start timestamp is not correct");
        assertEq(carrotVesting.duration(), DURATION, "Duration is not correct");
        assertEq(carrotVesting.steps(), STEPS, "Steps are not correct");
        assertEq(carrotVesting.maxCarrotAmount(), MAX_CARROT_AMOUNT, "Max carrot amount is not correct");
        assertEq(carrotVesting.totalPufferRewards(), TOTAL_PUFFER_REWARDS, "Total puffer rewards are not correct");
        assertEq(
            carrotVesting.exchangeRate(),
            1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT,
            "Exchange rate is not correct"
        );
    }

    function test_deposit_NotStarted() public {
        vm.expectRevert(CarrotVestingMulti.NotStarted.selector);
        carrotVesting.deposit(100 ether);
    }

    function test_deposit_MaxCarrotAmountReached() public initialized {
        uint256 overTheLimitAmount = MAX_CARROT_AMOUNT + 1;
        deal(address(carrot), alice, overTheLimitAmount);
        vm.startPrank(alice);
        carrot.approve(address(carrotVesting), overTheLimitAmount);
        vm.expectRevert(CarrotVestingMulti.MaxCarrotAmountReached.selector);
        carrotVesting.deposit(overTheLimitAmount);
        vm.stopPrank();
    }

    function test_deposit_MaxCarrotAmountReached2() public initialized {
        deal(address(carrot), alice, MAX_CARROT_AMOUNT);
        vm.startPrank(alice);
        carrot.approve(address(carrotVesting), MAX_CARROT_AMOUNT);
        carrotVesting.deposit(MAX_CARROT_AMOUNT);
        vm.stopPrank();
        vm.startPrank(bob);
        carrot.approve(address(carrotVesting), 1);
        vm.expectRevert(CarrotVestingMulti.MaxCarrotAmountReached.selector);
        carrotVesting.deposit(1);
        vm.stopPrank();
    }

    function test_deposit() public initialized {
        uint256 carrotBalanceBefore = carrot.balanceOf(alice);
        uint256 depositAmount = 100 ether;
        _deposit(alice, depositAmount);

        uint256 carrotBalanceAfter = carrot.balanceOf(alice);
        assertEq(carrotBalanceAfter, carrotBalanceBefore - depositAmount, "Carrot balance is not correct");
        assertEq(carrot.balanceOf(dead), depositAmount, "Carrot is not burned");

        _checkVesting(alice, depositAmount, 0, block.timestamp, block.timestamp, 0);
    }

    function test_deposit_multiple() public initialized {
        uint256 depositAmount1 = 100 ether;
        _deposit(alice, depositAmount1);
        uint256 initTimestamp1 = block.timestamp;

        skip(45 days);

        uint256 depositAmount2 = 200 ether;
        _deposit(alice, depositAmount2);

        uint256 initTimestamp2 = block.timestamp;

        assertEq(carrotVesting.getVestingInfo(alice).length, 2, "Vesting info is not correct");

        _checkVesting(alice, depositAmount1, 0, initTimestamp1, initTimestamp1, 0);
        _checkVesting(alice, depositAmount2, 0, initTimestamp2, initTimestamp2, 1);
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
        vm.expectRevert(CarrotVestingMulti.NotStarted.selector);
        carrotVesting.depositWithPermit(permit);
        vm.stopPrank();
    }

    function test_depositWithPermit_MaxCarrotAmountReached() public initialized {
        uint256 overTheLimitAmount = MAX_CARROT_AMOUNT + 1;
        deal(address(carrot), alice, overTheLimitAmount);

        // Generate a valid permit
        Permit memory permit = _signPermit(
            "alice",
            address(carrotVesting),
            overTheLimitAmount,
            block.timestamp + 1000,
            IERC20Permit(address(carrot)).DOMAIN_SEPARATOR()
        );

        vm.startPrank(alice);
        vm.expectRevert(CarrotVestingMulti.MaxCarrotAmountReached.selector);
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
        emit CarrotVestingMulti.Deposited(alice, depositAmount);
        carrotVesting.depositWithPermit(permit);
        vm.stopPrank();

        uint256 carrotBalanceAfter = carrot.balanceOf(alice);
        assertEq(carrotBalanceAfter, carrotBalanceBefore - depositAmount, "Carrot balance is not correct");
        assertEq(carrot.balanceOf(dead), depositAmount, "Carrot is not burned");

        _checkVesting(alice, depositAmount, 0, block.timestamp, block.timestamp, 0);
    }

    function test_depositWithPermit_multiple() public initialized {
        uint256 carrotBalanceBefore = carrot.balanceOf(alice);
        uint256 depositAmount = 100 ether;

        // Generate a valid permit
        Permit memory permit1 = _signPermit(
            "alice",
            address(carrotVesting),
            depositAmount,
            block.timestamp + 1000,
            IERC20Permit(address(carrot)).DOMAIN_SEPARATOR()
        );

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit CarrotVestingMulti.Deposited(alice, depositAmount);
        carrotVesting.depositWithPermit(permit1);
        vm.stopPrank();

        uint256 carrotBalanceAfter = carrot.balanceOf(alice);
        assertEq(carrotBalanceAfter, carrotBalanceBefore - depositAmount, "Carrot balance is not correct");
        assertEq(carrot.balanceOf(dead), depositAmount, "Carrot is not burned");

        _checkVesting(alice, depositAmount, 0, block.timestamp, block.timestamp, 0);

        skip(35 days);

        uint256 depositAmount2 = 200 ether;
        // Generate a valid permit
        Permit memory permit2 = _signPermit(
            "alice",
            address(carrotVesting),
            depositAmount2,
            block.timestamp + 1000,
            IERC20Permit(address(carrot)).DOMAIN_SEPARATOR()
        );

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit CarrotVestingMulti.Deposited(alice, depositAmount2);
        carrotVesting.depositWithPermit(permit2);
        vm.stopPrank();

        uint256 carrotBalanceAfter2 = carrot.balanceOf(alice);
        assertEq(
            carrotBalanceAfter2, carrotBalanceBefore - depositAmount2 - depositAmount, "Carrot balance is not correct"
        );
        assertEq(carrot.balanceOf(dead), depositAmount2 + depositAmount, "Carrot is not burned");

        _checkVesting(alice, depositAmount2, 0, block.timestamp, block.timestamp, 1);
    }

    function test_claim_NoClaimableAmount() public initialized {
        vm.startPrank(alice);
        vm.expectRevert(CarrotVestingMulti.NoClaimableAmount.selector);
        carrotVesting.claim();

        _deposit(alice, 100 ether);

        vm.expectRevert(CarrotVestingMulti.NoClaimableAmount.selector);
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
        vm.expectRevert(CarrotVestingMulti.NoClaimableAmount.selector);
        carrotVesting.claim();

        skip(1);

        uint256 expectedClaimableAmount = EXCHANGE_RATE * depositAmount / STEPS / 1e18;

        uint256 pufferBalanceBefore = puffer.balanceOf(alice);

        vm.expectEmit(true, true, true, false);
        emit CarrotVestingMulti.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        totalClaimedAmount += returnedClaimedAmount;
        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertApproxEqAbs(
            pufferBalanceAfter, pufferBalanceBefore + expectedClaimableAmount, 1, "Puffer balance is not correct"
        );

        _checkVesting(alice, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp, 0);

        skip(stepDuration);

        vm.expectEmit(true, true, true, false);
        emit CarrotVestingMulti.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        totalClaimedAmount += returnedClaimedAmount;

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter2 = puffer.balanceOf(alice);
        assertApproxEqAbs(
            pufferBalanceAfter2, pufferBalanceAfter + expectedClaimableAmount, 1, "Puffer balance is not correct"
        );

        _checkVesting(alice, depositAmount, expectedClaimableAmount * 2, block.timestamp, initTimestamp, 0);

        skip(DURATION);

        expectedClaimableAmount = totalExpectedClaimableAmount - totalClaimedAmount;

        vm.expectEmit(true, true, true, false);
        emit CarrotVestingMulti.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        totalClaimedAmount += returnedClaimedAmount;

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter3 = puffer.balanceOf(alice);
        assertApproxEqAbs(
            pufferBalanceAfter3, pufferBalanceAfter2 + expectedClaimableAmount, 1, "Puffer balance is not correct"
        );

        _checkVesting(alice, depositAmount, totalExpectedClaimableAmount, block.timestamp, initTimestamp, 0);

        vm.expectRevert(CarrotVestingMulti.NoClaimableAmount.selector);
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
        emit CarrotVestingMulti.Claimed(alice, expectedClaimableAmount);
        uint256 returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertEq(returnedClaimedAmount, expectedClaimableAmount, "Claimed amount is not correct");

        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertEq(pufferBalanceAfter, pufferBalanceBefore + expectedClaimableAmount, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp, 0);

        skip(2 * DURATION);

        vm.startPrank(alice);
        vm.expectRevert(CarrotVestingMulti.NoClaimableAmount.selector);
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
        emit CarrotVestingMulti.Claimed(alice, totalExpectedClaimableAmountAlice);
        uint256 returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertEq(returnedClaimedAmount, totalExpectedClaimableAmountAlice, "Claimed amount is not correct");

        _checkVesting(alice, depositAmountAlice, totalExpectedClaimableAmountAlice, block.timestamp, initTimestamp, 0);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, false);
        emit CarrotVestingMulti.Claimed(bob, totalExpectedClaimableAmountBob);
        returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertApproxEqAbs(puffer.balanceOf(address(carrotVesting)), 0, 1, "Puffer balance is not correct");
    }

    function test_claim_fuzzy(
        uint256 duration,
        uint256 steps,
        uint256 maxCarrotAmount,
        uint256 totalPufferRewards,
        uint256 depositAmount,
        uint256 waitTime
    ) public {
        duration = bound(duration, 10 days, 365 days);
        steps = bound(steps, 2, 100);
        maxCarrotAmount = bound(maxCarrotAmount, 100 ether, 100_000_000 ether);
        totalPufferRewards = bound(totalPufferRewards, 100 ether, 100_000_000 ether);
        depositAmount = bound(depositAmount, 1 ether, maxCarrotAmount);
        uint256 stepDuration = duration / steps;
        waitTime = bound(waitTime, stepDuration, duration);

        uint256 exchangeRate = totalPufferRewards * 1e18 / maxCarrotAmount;

        puffer.approve(address(carrotVesting), totalPufferRewards);
        carrotVesting.initialize(block.timestamp, duration, steps, maxCarrotAmount, totalPufferRewards);

        deal(address(carrot), alice, depositAmount);

        _deposit(alice, depositAmount);

        uint256 initTimestamp = block.timestamp;

        skip(waitTime);

        uint256 numStepsPassed = (block.timestamp - initTimestamp) / stepDuration;

        uint256 expectedClaimableAmount = (numStepsPassed * depositAmount / steps) * exchangeRate / 1e18;

        vm.startPrank(alice);
        vm.expectEmit(address(carrotVesting));
        emit CarrotVestingMulti.Claimed(alice, expectedClaimableAmount);
        uint256 returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");
        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertApproxEqAbs(pufferBalanceAfter, expectedClaimableAmount, 1, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp, 0);
    }

    function test_claim_multiple() public initialized {
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 2 * depositAmount1;
        uint256 expectedClaimableAmount;
        uint256 returnedClaimedAmount;
        uint256 totalClaimedAmount;
        _deposit(alice, depositAmount1);
        uint256 initTimestamp1 = block.timestamp;
        skip(45 days);
        _deposit(alice, depositAmount2);
        uint256 initTimestamp2 = block.timestamp;

        uint256 stepReward1 = (depositAmount1 / STEPS) * EXCHANGE_RATE / 1e18;
        uint256 stepReward2 = 2 * stepReward1;

        // 1 steps has passed since deposit1. 0 since deposit2
        expectedClaimableAmount = stepReward1;

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, false);
        emit CarrotVestingMulti.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");
        totalClaimedAmount += returnedClaimedAmount;

        assertApproxEqAbs(puffer.balanceOf(alice), totalClaimedAmount, 1, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount1, expectedClaimableAmount, block.timestamp, initTimestamp1, 0);
        _checkVesting(alice, depositAmount2, 0, initTimestamp2, initTimestamp2, 1);

        skip(55 days);

        // 3 steps have passed since deposit1. 1 since deposit2. 1st step from deposit1 was already claimed
        expectedClaimableAmount = 2 * stepReward1 + stepReward2;

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, false);
        emit CarrotVestingMulti.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 5, "Claimed amount is not correct");
        totalClaimedAmount += returnedClaimedAmount;

        assertApproxEqAbs(puffer.balanceOf(alice), totalClaimedAmount, 5, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount1, 3 * stepReward1, block.timestamp, initTimestamp1, 0);
        _checkVesting(alice, depositAmount2, stepReward2, block.timestamp, initTimestamp2, 1);
    }

    function test_claim_fuzzy2(
        uint256 duration,
        uint256 steps,
        uint256 maxCarrotAmount,
        uint256 totalPufferRewards,
        uint256 depositAmount,
        uint256 waitTime
    ) public {
        duration = bound(duration, 10 days, 365 days);
        steps = bound(steps, 2, 100);
        maxCarrotAmount = bound(maxCarrotAmount, 100 ether, 100_000_000 ether);
        totalPufferRewards = bound(totalPufferRewards, 100 ether, 100_000_000 ether);
        depositAmount = bound(depositAmount, 1 ether, maxCarrotAmount);
        uint256 stepDuration = duration / steps;
        waitTime = bound(waitTime, stepDuration, duration - stepDuration);

        uint256 exchangeRate = totalPufferRewards * 1e18 / maxCarrotAmount;
        uint256 totalExpectedClaimableAmount = exchangeRate * depositAmount / 1e18;

        puffer.approve(address(carrotVesting), totalPufferRewards);
        carrotVesting.initialize(block.timestamp, duration, steps, maxCarrotAmount, totalPufferRewards);

        deal(address(carrot), alice, depositAmount);

        _deposit(alice, depositAmount);

        uint256 initTimestamp = block.timestamp;

        skip(waitTime);

        uint256 numStepsPassed = (block.timestamp - initTimestamp) / stepDuration;

        uint256 expectedClaimableAmount = (numStepsPassed * depositAmount / steps) * exchangeRate / 1e18;

        vm.startPrank(alice);
        vm.expectEmit(address(carrotVesting));
        emit CarrotVestingMulti.Claimed(alice, expectedClaimableAmount);
        uint256 returnedClaimedAmount = carrotVesting.claim();

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertApproxEqAbs(pufferBalanceAfter, expectedClaimableAmount, 1, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp, 0);

        skip(duration);

        expectedClaimableAmount = totalExpectedClaimableAmount - expectedClaimableAmount;

        vm.expectEmit(address(carrotVesting));
        emit CarrotVestingMulti.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        assertEq(returnedClaimedAmount, expectedClaimableAmount, "Claimed amount is not correct");

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter2 = puffer.balanceOf(alice);
        assertApproxEqAbs(pufferBalanceAfter2, totalExpectedClaimableAmount, 1, "Puffer balance is not correct");

        _checkVesting(alice, depositAmount, totalExpectedClaimableAmount, block.timestamp, initTimestamp, 0);
    }

    function test_dismantle_Unauthorized() public initialized {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        carrotVesting.dismantle();
        vm.stopPrank();
    }

    function test_dismantle_NotEnoughTimePassed() public initialized {
        vm.expectRevert(CarrotVestingMulti.NotEnoughTimePassed.selector);
        carrotVesting.dismantle();
    }

    function test_dismantle() public initialized {
        skip(carrotVesting.MIN_TIME_TO_DISMANTLE_VESTING());
        vm.expectEmit(true, true, true, true);
        emit CarrotVestingMulti.Dismantled(TOTAL_PUFFER_REWARDS);
        carrotVesting.dismantle();
        assertTrue(carrotVesting.isDismantled(), "Vesting is not dismantled");

        vm.startPrank(alice);
        vm.expectRevert(CarrotVestingMulti.AlreadyDismantled.selector);
        carrotVesting.deposit(1 ether);

        vm.expectRevert(CarrotVestingMulti.AlreadyDismantled.selector);
        carrotVesting.claim();
        vm.stopPrank();
    }

    function _deposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        carrot.approve(address(carrotVesting), amount);
        vm.expectEmit(true, true, true, true);
        emit CarrotVestingMulti.Deposited(user, amount);
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
        uint256 expectedDepositedTimestamp,
        uint256 index
    ) internal view {
        (uint256 depositedAmount, uint256 claimedAmount, uint256 lastClaimedTimestamp, uint256 depositedTimestamp) =
            carrotVesting.vestings(user, index);
        assertApproxEqAbs(depositedAmount, expectedDepositedAmount, 5, "Deposited amount is not correct");
        assertApproxEqAbs(claimedAmount, expectedClaimedAmount, 5, "Claimed amount is not correct");
        assertEq(lastClaimedTimestamp, expectedLastClaimedTimestamp, "Last claimed timestamp is not correct");
        assertEq(depositedTimestamp, expectedDepositedTimestamp, "Deposited timestamp is not correct");
    }
}
