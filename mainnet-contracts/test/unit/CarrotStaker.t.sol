// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { CarrotStaker } from "../../src/CarrotStaker.sol";
import { ICarrotStaker } from "../../src/interface/ICarrotStaker.sol";
import { CARROT } from "../../src/CARROT.sol";

contract CarrotStakerTest is UnitTestHelper {
    CarrotStaker public staker;
    CARROT public carrot;

    address public admin;

    function setUp() public override {
        admin = makeAddr("admin");

        carrot = new CARROT(address(this));

        staker = new CarrotStaker(address(carrot), admin);

        carrot.transfer(alice, 1000 ether);
        carrot.transfer(bob, 1000 ether);
    }

    function test_constructor() public view {
        assertEq(address(staker.CARROT()), address(carrot));
        assertEq(staker.owner(), admin);
        assertEq(staker.name(), "Staked Carrot");
        assertEq(staker.symbol(), "sCarrot");
    }

    function test_stake() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(alice);
        carrot.approve(address(staker), stakeAmount);

        vm.expectEmit(true, true, true, true);
        emit ICarrotStaker.Staked({ staker: alice, amount: stakeAmount });
        staker.stake(stakeAmount);
        vm.stopPrank();

        assertEq(staker.balanceOf(alice), stakeAmount);
        assertEq(carrot.balanceOf(address(staker)), stakeAmount);
        assertEq(carrot.balanceOf(alice), 900 ether);
    }

    function test_unstake() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(alice);
        carrot.approve(address(staker), stakeAmount);
        staker.stake(stakeAmount);

        assertEq(staker.balanceOf(alice), stakeAmount);
        assertEq(carrot.balanceOf(address(staker)), stakeAmount);
        assertEq(carrot.balanceOf(alice), 900 ether);

        // Try to unstake before it's allowed
        vm.expectRevert(ICarrotStaker.UnstakingNotAllowed.selector);
        staker.unstake(stakeAmount, alice);
        vm.stopPrank();

        // Enable unstaking
        vm.prank(admin);
        staker.allowUnstake();

        // Now unstake should work
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ICarrotStaker.Unstaked({ staker: alice, recipient: alice, amount: stakeAmount });
        staker.unstake(stakeAmount, alice);
        vm.stopPrank();

        assertEq(staker.balanceOf(alice), 0);
        assertEq(carrot.balanceOf(address(staker)), 0);
        assertEq(carrot.balanceOf(alice), 1000 ether);
    }

    function test_allowUnstake() public {
        assertEq(staker.isUnstakingAllowed(), false);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICarrotStaker.UnstakingAllowed(true);
        staker.allowUnstake();

        assertEq(staker.isUnstakingAllowed(), true);
    }

    function test_allowUnstake_afterTimestamp() public {
        assertEq(staker.isUnstakingAllowed(), false);

        // Try to enable unstaking before timestamp as non-owner
        vm.prank(alice);
        vm.expectRevert(ICarrotStaker.UnauthorizedUnstakeEnable.selector);
        staker.allowUnstake();

        // Warp to after the unstaking open timestamp
        vm.warp(staker.UNSTAKING_OPEN_TIMESTAMP() + 1);

        // Now anyone should be able to enable unstaking
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ICarrotStaker.UnstakingAllowed(true);
        staker.allowUnstake();

        assertEq(staker.isUnstakingAllowed(), true);
    }

    function test_allowUnstake_ownerBeforeTimestamp() public {
        assertEq(staker.isUnstakingAllowed(), false);

        // Owner should be able to enable unstaking before timestamp
        vm.warp(staker.UNSTAKING_OPEN_TIMESTAMP() - 1 days);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICarrotStaker.UnstakingAllowed(true);
        staker.allowUnstake();

        assertEq(staker.isUnstakingAllowed(), true);
    }

    function test_transfer_reverts() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(alice);
        carrot.approve(address(staker), stakeAmount);
        staker.stake(stakeAmount);

        // Should revert when transferring sCarrot
        vm.expectRevert(ICarrotStaker.MethodNotAllowed.selector);
        staker.transfer(bob, stakeAmount);

        // Should revert even if approve method is called
        vm.expectRevert(ICarrotStaker.MethodNotAllowed.selector);
        staker.approve(bob, stakeAmount);
        vm.stopPrank();
    }

    function testFuzz_stake(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);

        vm.startPrank(alice);
        carrot.approve(address(staker), amount);

        vm.expectEmit(true, true, true, true);
        emit ICarrotStaker.Staked({ staker: alice, amount: amount });
        staker.stake(amount);
        vm.stopPrank();

        assertEq(staker.balanceOf(alice), amount);
        assertEq(carrot.balanceOf(address(staker)), amount);
        assertEq(carrot.balanceOf(alice), 1000 ether - amount);
    }

    function testFuzz_unstake(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);

        vm.startPrank(alice);
        carrot.approve(address(staker), amount);
        staker.stake(amount);
        vm.stopPrank();

        // Enable unstaking
        vm.prank(admin);
        staker.allowUnstake();

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ICarrotStaker.Unstaked({ staker: alice, recipient: alice, amount: amount });
        staker.unstake(amount, alice);
        vm.stopPrank();

        assertEq(staker.balanceOf(alice), 0);
        assertEq(carrot.balanceOf(address(staker)), 0);
        assertEq(carrot.balanceOf(alice), 1000 ether);
    }
}
