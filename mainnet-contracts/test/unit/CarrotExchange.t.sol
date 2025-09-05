// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { CarrotExchange } from "../../src/CarrotExchange.sol";
import { CARROT } from "../../src/CARROT.sol";
import { PUFFER } from "../../src/PUFFER.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { InvalidAddress, InvalidAmount } from "../../src/Errors.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

contract CarrotExchangeTest is Test {
    CarrotExchange public carrotExchange;
    CARROT public carrot;
    PUFFER public puffer;

    uint256 public constant TOTAL_PUFFER_REWARDS = 55_000_000 ether;
    uint256 public constant MAX_CARROT_AMOUNT = 100_000_000 ether;
    uint256 public constant EXCHANGE_RATE = 1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT;

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public dead = address(0xDEAD);
    address public treasury = makeAddr("treasury");

    function setUp() public {
        carrot = new CARROT(address(this));
        puffer = new PUFFER(address(this));
        carrotExchange = new CarrotExchange(address(carrot), address(puffer), address(this));

        puffer.unpause();
        carrot.transfer(alice, 100_000 ether);
        carrot.transfer(bob, 100_000 ether);

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(treasury, "treasury");
        vm.label(address(carrotExchange), "carrotExchange");
        vm.label(address(carrot), "carrot");
        vm.label(address(puffer), "puffer");
    }

    modifier initialized() {
        puffer.approve(address(carrotExchange), TOTAL_PUFFER_REWARDS);
        vm.expectEmit(true, true, true, true);
        emit CarrotExchange.Initialized(uint48(block.timestamp), uint48(block.timestamp + 365 days));
        carrotExchange.initialize(uint48(block.timestamp));
        _;
    }

    function test_constructor() public {
        assertEq(address(carrotExchange.CARROT()), address(carrot));
        assertEq(address(carrotExchange.PUFFER()), address(puffer));
        assertEq(carrotExchange.owner(), address(this));

        vm.expectRevert(InvalidAddress.selector);
        new CarrotExchange(address(0), address(puffer), address(this));
        vm.expectRevert(InvalidAddress.selector);
        new CarrotExchange(address(carrot), address(0), address(this));
    }

    function test_initialize_AlreadyInitialized() public initialized {
        vm.expectRevert(CarrotExchange.AlreadyInitialized.selector);
        carrotExchange.initialize(uint48(block.timestamp));
    }

    function test_initialize_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        carrotExchange.initialize(uint48(block.timestamp));
        vm.stopPrank();
    }

    function test_initialize_InvalidStartTimestamp() public {
        vm.expectRevert(CarrotExchange.InvalidStartTimestamp.selector);
        carrotExchange.initialize(uint48(block.timestamp - 1));
    }

    function test_initialize() public {
        puffer.approve(address(carrotExchange), TOTAL_PUFFER_REWARDS);
        vm.expectEmit(true, true, true, true);
        emit CarrotExchange.Initialized(uint48(block.timestamp), uint48(block.timestamp + 365 days));
        carrotExchange.initialize(uint48(block.timestamp));
        assertEq(carrotExchange.startTimestamp(), uint48(block.timestamp));
        assertEq(carrotExchange.pufferRecoveryMinTimestamp(), uint48(block.timestamp + 365 days));
        assertEq(carrotExchange.PUFFER().balanceOf(address(carrotExchange)), TOTAL_PUFFER_REWARDS);
    }

    function test_swapCarrotToPuffer_NotStarted() public {
        vm.startPrank(alice);
        carrot.approve(address(carrotExchange), 100 ether);
        vm.expectRevert(CarrotExchange.NotStarted.selector);
        carrotExchange.swapCarrotToPuffer(100 ether);
        vm.stopPrank();
    }

    function test_swapCarrotToPuffer_NotStarted2() public {
        puffer.approve(address(carrotExchange), TOTAL_PUFFER_REWARDS);
        carrotExchange.initialize(uint48(block.timestamp + 30 days));
        vm.startPrank(alice);
        carrot.approve(address(carrotExchange), 100 ether);
        vm.expectRevert(CarrotExchange.NotStarted.selector);
        carrotExchange.swapCarrotToPuffer(100 ether);
        vm.stopPrank();
    }

    function test_swapCarrotToPuffer_InvalidAmount() public initialized {
        vm.startPrank(alice);
        carrot.approve(address(carrotExchange), 0);
        vm.expectRevert(InvalidAmount.selector);
        carrotExchange.swapCarrotToPuffer(0);
        vm.stopPrank();
    }

    function test_swapCarrotToPuffer() public initialized {
        uint256 prevCarrotBalance = carrot.balanceOf(address(alice));
        uint256 carrotAmount = 100 ether;
        uint256 expectedPufferAmount = carrotAmount * EXCHANGE_RATE / 1e18;
        vm.startPrank(alice);
        carrot.approve(address(carrotExchange), carrotAmount);
        vm.expectEmit(true, true, true, true);
        emit CarrotExchange.CarrotToPufferSwapped(alice, carrotAmount, expectedPufferAmount);
        carrotExchange.swapCarrotToPuffer(carrotAmount);
        vm.stopPrank();

        assertEq(carrot.balanceOf(address(alice)), prevCarrotBalance - carrotAmount);
        assertEq(carrot.balanceOf(address(carrotExchange)), 0);
        assertEq(puffer.balanceOf(alice), expectedPufferAmount);
        assertEq(carrotExchange.totalCarrotsBurned(), carrotAmount);
    }

    function test_swapCarrotToPufferWithPermit() public initialized {
        uint256 prevCarrotBalance = carrot.balanceOf(address(alice));
        uint256 carrotAmount = 100 ether;
        uint256 expectedPufferAmount = carrotAmount * EXCHANGE_RATE / 1e18;

        // Generate a valid permit
        Permit memory permit = _signPermit(
            "alice",
            address(carrotExchange),
            carrotAmount,
            block.timestamp + 1000,
            IERC20Permit(address(carrot)).DOMAIN_SEPARATOR()
        );

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit CarrotExchange.CarrotToPufferSwapped(alice, carrotAmount, expectedPufferAmount);
        carrotExchange.swapCarrotToPufferWithPermit(permit);
        vm.stopPrank();

        assertEq(carrot.balanceOf(address(alice)), prevCarrotBalance - carrotAmount);
        assertEq(carrot.balanceOf(address(carrotExchange)), 0);
        assertEq(puffer.balanceOf(alice), expectedPufferAmount);
        assertEq(carrotExchange.totalCarrotsBurned(), carrotAmount);
    }

    function test_recoverPuffer_Unauthorized() public initialized {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        carrotExchange.recoverPuffer(alice);
        vm.stopPrank();
    }

    function test_recoverPuffer_InvalidAddress() public initialized {
        vm.expectRevert(InvalidAddress.selector);
        carrotExchange.recoverPuffer(address(0));
    }

    function test_recoverPuffer_NotEnoughTimePassed() public initialized {
        vm.expectRevert(CarrotExchange.NotEnoughTimePassed.selector);
        carrotExchange.recoverPuffer(alice);
    }

    function test_recoverPuffer_Full() public initialized {
        vm.warp(carrotExchange.pufferRecoveryMinTimestamp() + 1);
        uint256 prevPufferBalance = puffer.balanceOf(address(carrotExchange));
        vm.expectEmit(true, true, true, true);
        emit CarrotExchange.PufferRecovered(alice, prevPufferBalance);
        carrotExchange.recoverPuffer(alice);
        assertEq(puffer.balanceOf(alice), prevPufferBalance);
        assertEq(carrotExchange.carrotExchangeFinished(), true);
        assertEq(puffer.balanceOf(address(carrotExchange)), 0);

        vm.startPrank(bob);
        uint256 carrotAmount = 35 ether;
        carrot.approve(address(carrotExchange), carrotAmount);
        vm.expectRevert(CarrotExchange.CarrotExchangeFinished.selector);
        carrotExchange.swapCarrotToPuffer(carrotAmount);
        vm.stopPrank();
    }

    function test_recoverPuffer_Partial() public initialized {
        vm.startPrank(bob);
        uint256 carrotAmount = 35 ether;
        carrot.approve(address(carrotExchange), carrotAmount);
        carrotExchange.swapCarrotToPuffer(carrotAmount);
        vm.stopPrank();
        vm.warp(carrotExchange.pufferRecoveryMinTimestamp() + 1);
        uint256 prevPufferBalance = puffer.balanceOf(address(carrotExchange));
        vm.expectEmit(true, true, true, true);
        emit CarrotExchange.PufferRecovered(alice, prevPufferBalance);
        carrotExchange.recoverPuffer(alice);
        assertEq(puffer.balanceOf(alice), prevPufferBalance);
        assertEq(carrotExchange.carrotExchangeFinished(), true);
        assertEq(puffer.balanceOf(address(carrotExchange)), 0);
    }

    function test_pause_Unauthorized() public initialized {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        carrotExchange.pause();
        vm.stopPrank();
    }

    function test_pause() public initialized {
        vm.expectEmit(true, true, true, true);
        emit Pausable.Paused(address(this));
        carrotExchange.pause();

        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        carrotExchange.swapCarrotToPuffer(100 ether);
        vm.stopPrank();
    }

    function test_unpause_Unauthorized() public initialized {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        carrotExchange.unpause();
        vm.stopPrank();
    }

    function test_unpause() public initialized {
        carrotExchange.pause();
        vm.expectEmit(true, true, true, true);
        emit Pausable.Unpaused(address(this));
        carrotExchange.unpause();
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
}
