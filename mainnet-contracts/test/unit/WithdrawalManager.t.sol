// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { WithdrawalManager } from "src/WithdrawalManager.sol";
import { PufferVaultV2 } from "src/PufferVaultV2.sol";
import { ROLE_ID_PUFFER_PROTOCOL } from "../../script/Roles.sol";

/**
 * @title WithdrawalManagerTest
 * @dev Test contract for WithdrawalManager
 */
contract WithdrawalManagerTest is UnitTestHelper {
    WithdrawalManager public withdrawalManager;

    address[] public actors;

    /**
     * @dev Set up the test environment
     */
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

    /**
     * @dev Test creating deposits
     * @param numberOfDeposits The number of deposits to create
     */
    function test_createDeposits(uint8 numberOfDeposits) public {
        vm.assume(numberOfDeposits > 20);

        for (uint256 i = 0; i < numberOfDeposits; i++) {
            uint256 depositAmount = bound(i, 1 ether, 10 ether);
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);

            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawals(depositAmount, actor);
            vm.stopPrank();
        }
    }

    /**
     * @dev Fuzz test for requesting withdrawals
     * @param pufETHAmount The amount of pufETH to withdraw
     */
    function test_fuzz_requestWithdrawals(uint256 pufETHAmount) public {
        vm.assume(pufETHAmount >= 0.01 ether && pufETHAmount <= 1000 ether);

        address actor = actors[0];
        _givePufETH(pufETHAmount, actor);

        vm.startPrank(actor);
        pufferVault.approve(address(withdrawalManager), pufETHAmount);
        withdrawalManager.requestWithdrawals(pufETHAmount, actor);
        vm.stopPrank();

        (uint128 amount, , address recipient) = withdrawalManager.withdrawals(0);
        assertEq(uint256(amount), pufETHAmount, "Incorrect withdrawal amount");
        assertEq(recipient, actor, "Incorrect withdrawal recipient");
    }

    /**
     * @dev Test requesting withdrawals with minimum amount
     */
    function test_requestWithdrawals_minAmount() public {
        uint256 minAmount = 0.01 ether;
        address actor = actors[0];
        _givePufETH(minAmount, actor);

        vm.startPrank(actor);
        pufferVault.approve(address(withdrawalManager), minAmount);
        withdrawalManager.requestWithdrawals(minAmount, actor);
        vm.stopPrank();

        (uint128 amount, , ) = withdrawalManager.withdrawals(0);
        assertEq(uint256(amount), minAmount, "Incorrect minimum withdrawal amount");
    }

    /**
     * @dev Test requesting withdrawals below minimum amount
     */
    function test_requestWithdrawals_belowMinAmount() public {
        uint256 belowMinAmount = 0.009 ether;
        address actor = actors[0];
        _givePufETH(belowMinAmount, actor);

        vm.startPrank(actor);
        pufferVault.approve(address(withdrawalManager), belowMinAmount);
        vm.expectRevert(WithdrawalManager.WithdrawalAmountTooLow.selector);
        withdrawalManager.requestWithdrawals(belowMinAmount, actor);
        vm.stopPrank();
    }

    /**
     * @dev Test finalizing withdrawals for multiple batches
     */
    function test_finalizeWithdrawals_multipleBatches() public {
        uint256 batchSize = 10;
        uint256 numBatches = 3;
        uint256 depositAmount = 1 ether;

        for (uint256 i = 0; i < batchSize * numBatches; i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);
            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawals(depositAmount, actor);
            vm.stopPrank();
        }

        withdrawalManager.finalizeWithdrawals(numBatches - 1);

        assertEq(withdrawalManager.finalizedWithdrawalBatch(), numBatches - 1, "Incorrect finalized batch index");
    }

    /**
     * @dev Test finalizing withdrawals with an incomplete batch
     */
    function test_finalizeWithdrawals_incompleteBatch() public {
        uint256 batchSize = 10;
        uint256 incompleteAmount = 9;
        uint256 depositAmount = 1 ether;

        for (uint256 i = 0; i < incompleteAmount; i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);
            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawals(depositAmount, actor);
            vm.stopPrank();
        }

        vm.expectRevert(WithdrawalManager.BatchNotFull.selector);
        withdrawalManager.finalizeWithdrawals(0);
    }

    /**
     * @dev Test completing a queued withdrawal that is not finalized
     */
    function test_completeQueuedWithdrawal_notFinalized() public {
        uint256 depositAmount = 1 ether;
        address actor = actors[0];
        _givePufETH(depositAmount, actor);

        vm.startPrank(actor);
        pufferVault.approve(address(withdrawalManager), depositAmount);
        withdrawalManager.requestWithdrawals(depositAmount, actor);
        vm.stopPrank();

        vm.expectRevert(WithdrawalManager.NotFinalized.selector);
        withdrawalManager.completeQueuedWithdrawal(0);
    }

    /**
     * @dev Test deposits and finalizing withdrawals
     */
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
