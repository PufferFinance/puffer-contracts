// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { CarrotRestaking } from "../../src/CarrotRestaking.sol";
import { ICarrotRestaking } from "../../src/interface/ICarrotRestaking.sol";
import { CARROT } from "../../src/CARROT.sol";

contract CarrotRestakingTest is UnitTestHelper {
    CarrotRestaking public restaking;
    CARROT public carrot;

    address public admin;

    function setUp() public override {
        admin = makeAddr("admin");

        carrot = new CARROT(address(this));

        restaking = new CarrotRestaking(address(carrot), admin);

        carrot.transfer(alice, 1000 ether);
        carrot.transfer(bob, 1000 ether);
    }

    function test_constructor() public view {
        assertEq(address(restaking.CARROT()), address(carrot));
        assertEq(restaking.owner(), admin);
        assertEq(restaking.name(), "Staked Carrot");
        assertEq(restaking.symbol(), "sCarrot");
    }

    function test_stake() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(alice);
        carrot.approve(address(restaking), stakeAmount);

        vm.expectEmit(true, true, true, true);
        emit ICarrotRestaking.Staked({ staker: alice, amount: stakeAmount });
        restaking.stake(stakeAmount);
        vm.stopPrank();

        assertEq(restaking.balanceOf(alice), stakeAmount);
        assertEq(carrot.balanceOf(address(restaking)), stakeAmount);
        assertEq(carrot.balanceOf(alice), 900 ether);
    }

    function test_unstake() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(alice);
        carrot.approve(address(restaking), stakeAmount);
        restaking.stake(stakeAmount);

        assertEq(restaking.balanceOf(alice), stakeAmount);
        assertEq(carrot.balanceOf(address(restaking)), stakeAmount);
        assertEq(carrot.balanceOf(alice), 900 ether);

        // Try to unstake before it's allowed
        vm.expectRevert(ICarrotRestaking.UnstakingNotAllowed.selector);
        restaking.unstake(stakeAmount, alice);
        vm.stopPrank();

        // Enable unstaking
        vm.prank(admin);
        restaking.allowUnstake();

        // Now unstake should work
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ICarrotRestaking.Unstaked({ staker: alice, recipient: alice, amount: stakeAmount });
        restaking.unstake(stakeAmount, alice);
        vm.stopPrank();

        assertEq(restaking.balanceOf(alice), 0);
        assertEq(carrot.balanceOf(address(restaking)), 0);
        assertEq(carrot.balanceOf(alice), 1000 ether);
    }

    function test_allowUnstake() public {
        assertEq(restaking.isUnstakingAllowed(), false);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICarrotRestaking.UnstakingAllowed({ allowed: true });
        restaking.allowUnstake();

        assertEq(restaking.isUnstakingAllowed(), true);
    }

    function test_transfer_reverts() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(alice);
        carrot.approve(address(restaking), stakeAmount);
        restaking.stake(stakeAmount);

        // Should revert when transferring sCarrot
        vm.expectRevert(ICarrotRestaking.TransferNotAllowed.selector);
        restaking.transfer(bob, stakeAmount);

        restaking.approve(bob, stakeAmount);
        vm.stopPrank();

        vm.prank(bob);
        // Should revert even if approved to someone else
        vm.expectRevert(ICarrotRestaking.TransferNotAllowed.selector);
        restaking.transferFrom(alice, bob, stakeAmount);
    }

    function testFuzz_stake(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);

        vm.startPrank(alice);
        carrot.approve(address(restaking), amount);

        vm.expectEmit(true, true, true, true);
        emit ICarrotRestaking.Staked({ staker: alice, amount: amount });
        restaking.stake(amount);
        vm.stopPrank();

        assertEq(restaking.balanceOf(alice), amount);
        assertEq(carrot.balanceOf(address(restaking)), amount);
        assertEq(carrot.balanceOf(alice), 1000 ether - amount);
    }

    function testFuzz_unstake(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);

        vm.startPrank(alice);
        carrot.approve(address(restaking), amount);
        restaking.stake(amount);
        vm.stopPrank();

        // Enable unstaking
        vm.prank(admin);
        restaking.allowUnstake();

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ICarrotRestaking.Unstaked({ staker: alice, recipient: alice, amount: amount });
        restaking.unstake(amount, alice);
        vm.stopPrank();

        assertEq(restaking.balanceOf(alice), 0);
        assertEq(carrot.balanceOf(address(restaking)), 0);
        assertEq(carrot.balanceOf(alice), 1000 ether);
    }
}
