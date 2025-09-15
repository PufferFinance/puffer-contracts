// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { CarrotVesting } from "../../src/CarrotVesting.sol";
import { CARROT } from "../../src/CARROT.sol";
import { PUFFER } from "../../src/PUFFER.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { Vesting } from "../../src/struct/CarrotVestingStruct.sol";
import { InvalidAddress } from "../../src/Errors.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
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
    address public treasury = makeAddr("treasury");

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        carrot = new CARROT(address(this));
        puffer = new PUFFER(address(this));
        bytes32 salt = bytes32("CarrotVesting");
        CarrotVesting carrotVestingImpl = new CarrotVesting{ salt: salt }(address(carrot), address(puffer));
        ERC1967Proxy proxy = new ERC1967Proxy(address(carrotVestingImpl), "");
        carrotVesting = CarrotVesting(payable(proxy));

        puffer.unpause();
        carrot.transfer(alice, 100_00 ether);
        carrot.transfer(bob, 100_00 ether);

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(treasury, "treasury");
    }

    modifier initialized() {
        puffer.approve(address(carrotVesting), TOTAL_PUFFER_REWARDS);
        vm.expectEmit(true, true, true, true);
        emit CarrotVesting.Initialized(block.timestamp, DURATION, STEPS);
        carrotVesting.initialize(uint48(block.timestamp), DURATION, STEPS, address(this));
        _;
    }

    function test_constructor() public {
        assertEq(address(carrotVesting.CARROT()), address(carrot), "CARROT address is not correct");
        assertEq(address(carrotVesting.PUFFER()), address(puffer), "PUFFER address is not correct");

        vm.expectRevert(InvalidAddress.selector);
        new CarrotVesting(address(0), address(puffer));
        vm.expectRevert(InvalidAddress.selector);
        new CarrotVesting(address(carrot), address(0));
    }

    function test_initialize_InvalidInitialization() public initialized {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        carrotVesting.initialize(uint48(block.timestamp), DURATION, STEPS, bob);
    }

    function test_initialize_failed() public {
        vm.expectRevert(CarrotVesting.InvalidStartTimestamp.selector);
        carrotVesting.initialize(uint48(block.timestamp - 1), DURATION, STEPS, address(this));
        vm.expectRevert(CarrotVesting.InvalidDuration.selector);
        carrotVesting.initialize(uint48(block.timestamp), 0, STEPS, address(this));
        vm.expectRevert(CarrotVesting.InvalidSteps.selector);
        carrotVesting.initialize(uint48(block.timestamp), DURATION, 0, address(this));
        vm.expectRevert(CarrotVesting.InvalidDuration.selector);
        carrotVesting.initialize(uint48(block.timestamp), DURATION, DURATION+1, address(this));
        vm.expectRevert(InvalidAddress.selector);
        carrotVesting.initialize(uint48(block.timestamp), DURATION, STEPS, address(0));
    }

    function test_initialize() public initialized {
        assertEq(carrotVesting.getStartTimestamp(), block.timestamp, "Start timestamp is not correct");
        assertEq(carrotVesting.getDuration(), DURATION, "Duration is not correct");
        assertEq(carrotVesting.getSteps(), STEPS, "Steps are not correct");
        assertEq(carrotVesting.getTotalDepositedAmount(), 0, "Total deposited amount is not correct");
        assertEq(
            carrotVesting.EXCHANGE_RATE(),
            1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT,
            "Exchange rate is not correct"
        );
    }

    function test_startVesting_NotStarted() public {
        vm.expectRevert(CarrotVesting.NotStarted.selector);
        carrotVesting.startVesting(100 ether);
    }

    function test_startVesting_InvalidAmount() public initialized {
        vm.expectRevert(CarrotVesting.InvalidAmount.selector);
        carrotVesting.startVesting(0);
    }

    function test_startVesting_Dismantled() public initialized {
        carrotVesting.recoverPuffer(treasury);
        vm.expectRevert(CarrotVesting.AlreadyDismantled.selector);
        carrotVesting.startVesting(100 ether);
    }

    function test_startVesting() public initialized {
        uint256 carrotBalanceBefore = carrot.balanceOf(alice);
        uint256 depositAmount = 100 ether;
        _startVesting(alice, depositAmount);

        uint256 carrotBalanceAfter = carrot.balanceOf(alice);
        assertEq(carrotBalanceAfter, carrotBalanceBefore - depositAmount, "Carrot balance is not correct");
        assertEq(carrot.balanceOf(dead), depositAmount, "Carrot is not burned");

        _checkVesting(alice, 0, depositAmount, 0, block.timestamp, block.timestamp);
    }

    function test_startVestingWithPermit_NotStarted() public {
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
        carrotVesting.startVestingWithPermit(permit);
        vm.stopPrank();
    }

    function test_startVestingWithPermit() public initialized {
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
        emit CarrotVesting.VestingStarted(alice, depositAmount);
        carrotVesting.startVestingWithPermit(permit);
        vm.stopPrank();

        uint256 carrotBalanceAfter = carrot.balanceOf(alice);
        assertEq(carrotBalanceAfter, carrotBalanceBefore - depositAmount, "Carrot balance is not correct");
        assertEq(carrot.balanceOf(dead), depositAmount, "Carrot is not burned");

        _checkVesting(alice, 0, depositAmount, 0, block.timestamp, block.timestamp);
    }

    function test_claim_NoClaimableAmount() public initialized {
        vm.startPrank(alice);
        vm.expectRevert(CarrotVesting.NoClaimableAmount.selector);
        carrotVesting.claim();

        _startVesting(alice, 100 ether);

        vm.expectRevert(CarrotVesting.NoClaimableAmount.selector);
        carrotVesting.claim();
        vm.stopPrank();
    }

    function test_claim_Dismantled() public initialized {
        carrotVesting.recoverPuffer(treasury);
        vm.expectRevert(CarrotVesting.AlreadyDismantled.selector);
        carrotVesting.claim();
    }

    function test_claim() public initialized {
        uint256 initTimestamp = block.timestamp;
        uint256 depositAmount = 100 ether;
        _startVesting(alice, depositAmount);

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
        {
            // Inside block to prevent Stack Too Deep
            uint256 calculatedClaimAmount = carrotVesting.calculateClaimableAmount(alice);
            assertApproxEqAbs(
                calculatedClaimAmount, expectedClaimableAmount, 1, "Calculated claimed amount is not correct"
            );
        }

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

        _checkVesting(alice, 0, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp);

        skip(stepDuration);

        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        {
            returnedClaimedAmount = carrotVesting.claim();
            totalClaimedAmount += returnedClaimedAmount;

            assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");
        }

        uint256 pufferBalanceAfter2 = puffer.balanceOf(alice);
        assertApproxEqAbs(
            pufferBalanceAfter2, pufferBalanceAfter + expectedClaimableAmount, 1, "Puffer balance is not correct"
        );

        _checkVesting(alice, 0, depositAmount, expectedClaimableAmount * 2, block.timestamp, initTimestamp);

        skip(DURATION);

        expectedClaimableAmount = totalExpectedClaimableAmount - totalClaimedAmount;

        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        {
            returnedClaimedAmount = carrotVesting.claim();
            totalClaimedAmount += returnedClaimedAmount;

            assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

            uint256 pufferBalanceAfter3 = puffer.balanceOf(alice);
            assertApproxEqAbs(
                pufferBalanceAfter3, pufferBalanceAfter2 + expectedClaimableAmount, 1, "Puffer balance is not correct"
            );
        }

        _checkVesting(alice, 0, depositAmount, totalExpectedClaimableAmount, block.timestamp, initTimestamp);

        vm.expectRevert(CarrotVesting.NoClaimableAmount.selector);
        carrotVesting.claim();
    }

    function test_claimAllAtOnce() public initialized {
        uint256 depositAmount = 100 ether;
        _startVesting(alice, depositAmount);
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

        _checkVesting(alice, 0, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp);

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

        _startVesting(alice, depositAmountAlice);
        _startVesting(bob, depositAmountBob);

        skip(DURATION);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, totalExpectedClaimableAmountAlice);
        uint256 returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertEq(returnedClaimedAmount, totalExpectedClaimableAmountAlice, "Claimed amount is not correct");

        _checkVesting(alice, 0, depositAmountAlice, totalExpectedClaimableAmountAlice, block.timestamp, initTimestamp);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(bob, totalExpectedClaimableAmountBob);
        returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertApproxEqAbs(puffer.balanceOf(address(carrotVesting)), 0, 1, "Puffer balance is not correct");
    }

    function test_claim_fuzzy(uint256 duration, uint256 steps, uint256 depositAmount, uint256 waitTime) public {
        duration = bound(duration, 10 days, 365 days);
        steps = bound(steps, 2, 100);
        depositAmount = bound(depositAmount, 1 ether, MAX_CARROT_AMOUNT);
        uint256 stepDuration = duration / steps;
        waitTime = bound(waitTime, stepDuration, duration);

        puffer.approve(address(carrotVesting), TOTAL_PUFFER_REWARDS);
        carrotVesting.initialize(uint48(block.timestamp), uint32(duration), uint32(steps), address(this));

        deal(address(carrot), alice, depositAmount);

        _startVesting(alice, depositAmount);

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

        _checkVesting(alice, 0, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp);
    }

    function test_claim_fuzzy2(uint256 duration, uint256 steps, uint256 depositAmount, uint256 waitTime) public {
        duration = bound(duration, 10 days, 365 days);
        steps = bound(steps, 2, 100);
        depositAmount = bound(depositAmount, 1 ether, MAX_CARROT_AMOUNT);
        uint256 stepDuration = duration / steps;
        waitTime = bound(waitTime, stepDuration, duration - stepDuration);

        uint256 totalExpectedClaimableAmount = EXCHANGE_RATE * depositAmount / 1e18;

        puffer.approve(address(carrotVesting), TOTAL_PUFFER_REWARDS);
        carrotVesting.initialize(uint48(block.timestamp), uint32(duration), uint32(steps), address(this));

        deal(address(carrot), alice, depositAmount);

        _startVesting(alice, depositAmount);

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

        _checkVesting(alice, 0, depositAmount, expectedClaimableAmount, block.timestamp, initTimestamp);

        skip(duration);

        expectedClaimableAmount = totalExpectedClaimableAmount - expectedClaimableAmount;

        vm.expectEmit(address(carrotVesting));
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount);
        returnedClaimedAmount = carrotVesting.claim();
        assertEq(returnedClaimedAmount, expectedClaimableAmount, "Claimed amount is not correct");

        assertApproxEqAbs(returnedClaimedAmount, expectedClaimableAmount, 1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter2 = puffer.balanceOf(alice);
        assertApproxEqAbs(pufferBalanceAfter2, totalExpectedClaimableAmount, 1, "Puffer balance is not correct");

        _checkVesting(alice, 0, depositAmount, totalExpectedClaimableAmount, block.timestamp, initTimestamp);
    }

    function test_multiVesting_Secuential() public initialized {
        uint256 depositAmount1 = 100 ether;
        _startVesting(alice, depositAmount1);
        uint256 initTimestamp = block.timestamp;

        uint256 pufferBalanceBefore = puffer.balanceOf(alice);
        uint256 expectedClaimableAmount1 = EXCHANGE_RATE * depositAmount1 / 1e18;

        skip(2 * DURATION);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount1);
        uint256 returnedClaimedAmount1 = carrotVesting.claim();
        vm.stopPrank();

        assertEq(returnedClaimedAmount1, expectedClaimableAmount1, "Claimed amount is not correct");

        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertEq(pufferBalanceAfter, pufferBalanceBefore + expectedClaimableAmount1, "Puffer balance is not correct");

        _checkVesting(alice, 0, depositAmount1, expectedClaimableAmount1, block.timestamp, initTimestamp);

        skip(2 * DURATION);
        uint256 depositAmount2 = 50 ether;
        _startVesting(alice, depositAmount2);
        uint256 initTimestamp2 = block.timestamp;

        uint256 pufferBalanceBefore2 = pufferBalanceAfter;
        uint256 expectedClaimableAmount2 = EXCHANGE_RATE * depositAmount2 / 1e18;

        skip(2 * DURATION);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount2);
        uint256 returnedClaimedAmount2 = carrotVesting.claim();
        vm.stopPrank();

        assertEq(returnedClaimedAmount2, expectedClaimableAmount2, "Claimed amount is not correct");

        uint256 pufferBalanceAfter2 = puffer.balanceOf(alice);
        assertEq(pufferBalanceAfter2, pufferBalanceBefore2 + expectedClaimableAmount2, "Puffer balance is not correct");

        _checkVesting(alice, 1, depositAmount2, expectedClaimableAmount2, block.timestamp, initTimestamp2);
    }

    function test_multiVesting_Simultaneous() public initialized {
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 50 ether;
        _startVesting(alice, depositAmount1);
        uint256 initTimestamp1 = block.timestamp;
        skip(DURATION / 2);
        _startVesting(alice, depositAmount2);
        uint256 initTimestamp2 = block.timestamp;
        skip(DURATION * 2);

        uint256 pufferBalanceBefore = puffer.balanceOf(alice);
        uint256 expectedClaimableAmount1 = EXCHANGE_RATE * depositAmount1 / 1e18;
        uint256 expectedClaimableAmount2 = EXCHANGE_RATE * depositAmount2 / 1e18;

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, false);
        emit CarrotVesting.Claimed(alice, expectedClaimableAmount1 + expectedClaimableAmount2);
        uint256 returnedClaimedAmount = carrotVesting.claim();
        vm.stopPrank();

        assertEq(
            returnedClaimedAmount, expectedClaimableAmount1 + expectedClaimableAmount2, "Claimed amount is not correct"
        );

        uint256 pufferBalanceAfter = puffer.balanceOf(alice);
        assertEq(
            pufferBalanceAfter,
            pufferBalanceBefore + expectedClaimableAmount1 + expectedClaimableAmount2,
            "Puffer balance is not correct"
        );

        _checkVesting(alice, 0, depositAmount1, expectedClaimableAmount1, block.timestamp, initTimestamp1);
        _checkVesting(alice, 1, depositAmount2, expectedClaimableAmount2, block.timestamp, initTimestamp2);
    }

    function test_recoverPuffer_Unauthorized() public initialized {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        carrotVesting.recoverPuffer(treasury);
        vm.stopPrank();
    }

    function test_recoverPuffer() public initialized {
        uint256 pufferBalanceBefore = puffer.balanceOf(address(carrotVesting));
        assertEq(pufferBalanceBefore, TOTAL_PUFFER_REWARDS, "Puffer initial balance is not correct");
        vm.expectEmit(true, true, true, true);
        emit CarrotVesting.PufferRecovered(TOTAL_PUFFER_REWARDS);
        uint256 pufferRecovered = carrotVesting.recoverPuffer(treasury);
        uint256 pufferBalanceAfter = puffer.balanceOf(address(carrotVesting));
        uint256 pufferTreasuryBalance = puffer.balanceOf(treasury);
        assertEq(pufferBalanceAfter, 0, "Puffer balance is not correct");
        assertEq(pufferTreasuryBalance, pufferRecovered, "Puffer treasury balance is not correct");
        assertEq(pufferBalanceBefore, pufferRecovered, "Puffer treasury balance is not correct");
        assertEq(carrotVesting.isDismantled(), true, "Contract is not dismantled");
    }

    function test_pause_Unauthorized() public initialized {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        carrotVesting.pause();
        vm.stopPrank();
    }

    function test_pause() public initialized {
        vm.expectEmit(true, true, true, true);
        emit Pausable.Paused(address(this));
        carrotVesting.pause();

        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        carrotVesting.startVesting(1 ether);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        carrotVesting.claim();
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit CarrotVesting.PufferRecovered(TOTAL_PUFFER_REWARDS);
        carrotVesting.recoverPuffer(treasury); // Recover should still work
    }

    function test_unpause_Unauthorized() public initialized {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        carrotVesting.unpause();
        vm.stopPrank();
    }

    function test_unpause() public initialized {
        carrotVesting.pause();
        vm.expectEmit(true, true, true, true);
        emit Pausable.Unpaused(address(this));
        carrotVesting.unpause();

        // Not reverting
        _startVesting(alice, 100 ether);
        skip(DURATION * 2);
        vm.startPrank(alice);
        carrotVesting.claim();
        vm.stopPrank();
    }

    function test_upgrade() public initialized {
        ERC20Mock mockCarrot = new ERC20Mock("MockCarrot", "MOCK_CARROT");
        carrotVesting.upgradeToAndCall(address(new CarrotVesting(address(mockCarrot), address(puffer))), "");

        assertEq(address(carrotVesting.CARROT()), address(mockCarrot), "CARROT address is not correct");
    }

    function _startVesting(address user, uint256 amount) internal {
        vm.startPrank(user);
        carrot.approve(address(carrotVesting), amount);
        vm.expectEmit(true, true, true, true);
        emit CarrotVesting.VestingStarted(user, amount);
        carrotVesting.startVesting(amount);
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
        uint256 index,
        uint256 expectedDepositedAmount,
        uint256 expectedClaimedAmount,
        uint256 expectedLastClaimedTimestamp,
        uint256 expectedDepositedTimestamp
    ) internal view {
        Vesting memory vesting = carrotVesting.getVestings(user)[index];
        assertApproxEqAbs(vesting.depositedAmount, expectedDepositedAmount, 1, "Deposited amount is not correct");
        assertApproxEqAbs(vesting.claimedAmount, expectedClaimedAmount, 1, "Claimed amount is not correct");
        assertApproxEqAbs(
            vesting.lastClaimedTimestamp, expectedLastClaimedTimestamp, 1, "Last claimed timestamp is not correct"
        );
        assertApproxEqAbs(
            vesting.depositedTimestamp, expectedDepositedTimestamp, 1, "Deposited timestamp is not correct"
        );
    }
}
