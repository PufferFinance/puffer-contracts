// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { WithdrawalManager } from "../../src/WithdrawalManager.sol";
import { PufferVaultV2 } from "../../src/PufferVaultV2.sol";
import { ROLE_ID_PUFFER_PROTOCOL } from "../../script/Roles.sol";

contract WithdrawalManagerTest is UnitTestHelper {
    WithdrawalManager public withdrawalManager;

    address[] public actors;

    function setUp() public override {
        super.setUp();
        withdrawalManager = new WithdrawalManager(pufferVault);

        vm.startPrank(timelock);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PufferVaultV2.transferETH.selector;
        accessManager.setTargetFunctionRole(address(pufferVault), selectors, ROLE_ID_PUFFER_PROTOCOL);
        accessManager.grantRole(ROLE_ID_PUFFER_PROTOCOL, address(withdrawalManager), 0);
        vm.stopPrank();

        // Initialize actors
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("charlie"));
        actors.push(makeAddr("dianna"));
        actors.push(makeAddr("ema"));
        actors.push(makeAddr("filip"));
        actors.push(makeAddr("george"));
        actors.push(makeAddr("harry"));
        actors.push(makeAddr("isabelle"));
        actors.push(makeAddr("james"));
    }

    function test_createDeposits(uint8 numberOfDeposits) public {
        vm.assume(numberOfDeposits > 20);

        for (uint256 i = 0; i < numberOfDeposits; i++) {
            uint256 depositAmount = i;
            address actor = actors[i % actors.length];
            depositAmount = bound(depositAmount, 1 ether, 10 ether);
            _givePufETH(depositAmount, actor);

            vm.prank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            vm.prank(actor);
            withdrawalManager.requestWithdrawals(depositAmount, actor);
        }
    }

    function test_depositsAndFinalizeWithdrawals() public {
        uint256 depositAmount = 1 ether;

        // At this point in time, the vault has 1000 ETH and the exchange rate is 1:1
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "1:1 exchange rate");
        assertEq(pufferVault.totalAssets(), 1000 ether, "total assets");

        // Users request withdrawals, we record the exchange rate (1:1)
        for (uint256 i = 0; i < 10; i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);
            vm.prank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            vm.prank(actor);
            withdrawalManager.requestWithdrawals(depositAmount, actor);
        }

        assertEq(pufferVault.totalAssets(), 1010 ether, "total assets");

        // deposit 300 to change the exchange rate
        _vtSale(300 ether);

        assertEq(pufferVault.totalAssets(), 1310 ether, "total assets");

        withdrawalManager.finalizeWithdrawals(0);

        for (uint256 i = 0; i < 10; i++) {
            address actor = actors[i % actors.length];

            vm.startPrank(actor);

            vm.expectEmit(true, true, true, true);
            emit WithdrawalManager.WithdrawalCompleted(i, depositAmount, 1 ether, actor);
            withdrawalManager.completeQueuedWithdrawal(i);

            // the users did not get any yield from the VT sale, they got paid out using the original 1:1 exchange rate
            assertEq(actor.balance, depositAmount, "actor got paid in ETH");
        }
    }

    function test_protocolSlashing() public {
        uint256 depositAmount = 1 ether;

        // At this point in time, the vault has 1000 ETH and the exchange rate is 1:1
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "1:1 exchange rate");
        assertEq(pufferVault.totalAssets(), 1000 ether, "total assets");

        // Users request withdrawals, we record the exchange rate (1:1)
        for (uint256 i = 0; i < 10; i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);
            vm.prank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            vm.prank(actor);
            withdrawalManager.requestWithdrawals(depositAmount, actor);
        }

        assertEq(pufferVault.totalAssets(), 1010 ether, "total assets");

        // Simulate a slashing, the vault now has 900 ETH instead of 1000
        deal(address(pufferVault), 900 ether);

        assertEq(pufferVault.totalAssets(), 900 ether, "total assets 900");

        // The settlement exchange rate is now lower than the original 1:1 exchange rate
        withdrawalManager.finalizeWithdrawals(0);

        for (uint256 i = 0; i < 10; i++) {
            address actor = actors[i % actors.length];

            vm.startPrank(actor);
            withdrawalManager.completeQueuedWithdrawal(i);

            // the users will get less than 1 ETH because of the slashing
            assertEq(actor.balance, 0.891089108910891089 ether, "actor got paid in ETH");
        }
    }

    function test_constructor() public {
        new WithdrawalManager(pufferVault);
    }

    function test_requestWithdrawals() public {
        _givePufETH(1 ether, address(this));

        pufferVault.approve(address(withdrawalManager), 1 ether);
        withdrawalManager.requestWithdrawals(1 ether, address(this));
    }

    function _givePufETH(uint256 amount, address recipient) internal {
        vm.deal(address(this), amount);

        pufferVault.depositETH{ value: amount }(recipient);
    }

    // Simulates VT sale affects the exchange rate
    function _vtSale(uint256 amount) internal {
        vm.deal(address(this), amount);

        payable(address(pufferVault)).transfer(amount);
    }
}
