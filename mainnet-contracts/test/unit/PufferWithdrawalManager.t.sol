// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { PufferWithdrawalManager } from "src/PufferWithdrawalManager.sol";
import { PufferWithdrawalManagerStorage } from "src/PufferWithdrawalManagerStorage.sol";
import { IPufferWithdrawalManager } from "src/interface/IPufferWithdrawalManager.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { Generate2StepWithdrawalsCalldata } from
    "../../script/AccessManagerMigrations/04_Generate2StepWithdrawalsCalldata.s.sol";
/**
 * @title PufferWithdrawalManagerTest
 * @dev Test contract for PufferWithdrawalManager
 *
 * @dev Run the following command to execute the tests:
 * forge test --match-path test/unit/PufferWithdrawalManager.t.sol -vvvv
 */

contract PufferWithdrawalManagerTest is UnitTestHelper {
    PufferWithdrawalManager public withdrawalManager;

    address[] public actors;

    uint256 public batchSize;

    // 1 VT = 0.00247825075 ETH on mainnet at the time of writing
    uint256 public VT_PRICE = 0.00247825075 ether;

    /**
     * @dev Set up the test environment
     */
    function setUp() public override {
        super.setUp();

        PufferWithdrawalManager withdrawalManagerImpl = ((new PufferWithdrawalManager(10, pufferVault, weth)));

        batchSize = withdrawalManagerImpl.BATCH_SIZE();

        // deploy an ERC1967Proxy
        withdrawalManager = PufferWithdrawalManager(
            (
                payable(
                    new ERC1967Proxy{ salt: bytes32("PufferWithdrawalManager") }(
                        address(withdrawalManagerImpl),
                        abi.encodeCall(PufferWithdrawalManager.initialize, address(accessManager))
                    )
                )
            )
        );

        vm.label(address(withdrawalManager), "PufferWithdrawalManager");

        vm.startPrank(_broadcaster);

        bytes memory encodedCalldata =
            new Generate2StepWithdrawalsCalldata().run(address(withdrawalManager), address(pufferVault));
        (bool success,) = address(accessManager).call(encodedCalldata);
        require(success, "AccessManager.call failed");

        vm.stopPrank();

        // Initialize actors
        actors.push(alice);
        actors.push(bob);
        actors.push(charlie);
        actors.push(dianna);
        actors.push(ema);
        actors.push(filip);
        actors.push(george);
        actors.push(harry);
        actors.push(isabelle);
        actors.push(james);
    }

    function test_biggerBatchSizeUpgrade() public {
        vm.startPrank(address(timelock));

        address newImpl = address(new PufferWithdrawalManager(1234, pufferVault, weth));

        vm.expectRevert(IPufferWithdrawalManager.BatchSizeCannotChange.selector);
        withdrawalManager.upgradeToAndCall(newImpl, "");
    }

    /**
     * @dev Test creating deposits
     * @param numberOfDeposits The number of deposits to create
     */
    function test_createDeposits(uint8 numberOfDeposits) public {
        vm.assume(numberOfDeposits > 30);

        for (uint256 i = 0; i < numberOfDeposits; i++) {
            uint256 depositAmount = vm.randomUint(1 ether, 10 ether);
            address actor = actors[i % actors.length];
            _createDeposit(depositAmount, actor);
        }

        assertEq(
            withdrawalManager.getWithdrawalsLength(), numberOfDeposits + batchSize, "Incorrect number of withdrawals"
        );
        assertEq(withdrawalManager.getFinalizedWithdrawalBatch(), 0, "finalizedWithdrawalBatch should be 0");
    }

    /**
     * Resource heavy test, so we restrict the number of runs
     * forge-config: default.fuzz.runs = 10
     * forge-config: default.fuzz.show-logs = false
     * forge-config: ci.fuzz.runs = 10
     */
    function test_createAndFinalizeWithdrawals(uint8 numberOfDeposits) public {
        vm.assume(numberOfDeposits > 200);

        vm.pauseGasMetering();

        for (uint256 i = 0; i < numberOfDeposits; i++) {
            if (i % 2 == 0) {
                uint256 vtSaleAmount = vm.randomUint(1, 100) * VT_PRICE;
                _vtSale(vtSaleAmount);
            }

            uint256 ethDepositAmount = vm.randomUint(0.01 ether, 1000 ether);
            address actor = actors[i % actors.length];
            _createDeposit(ethDepositAmount, actor);
        }

        uint256 numBatches = numberOfDeposits / batchSize;

        vm.prank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(numBatches);

        for (uint256 i = batchSize; i < numberOfDeposits; i++) {
            vm.prank(actors[i % actors.length]);

            withdrawalManager.completeQueuedWithdrawal(i);
        }
    }

    /**
     * @dev Fuzz test for requesting withdrawals
     * @param pufETHAmount The amount of pufETH to withdraw
     */
    function test_fuzz_requestWithdrawals(uint256 pufETHAmount) public {
        vm.assume(pufETHAmount >= 0.01 ether && pufETHAmount <= 1000 ether);

        _givePufETH(pufETHAmount, alice);

        vm.startPrank(alice);
        pufferVault.approve(address(withdrawalManager), pufETHAmount);
        withdrawalManager.requestWithdrawal(uint128(pufETHAmount), alice);
        vm.stopPrank();

        PufferWithdrawalManagerStorage.Withdrawal memory withdrawal = withdrawalManager.getWithdrawal(batchSize);
        assertEq(uint256(withdrawal.pufETHAmount), pufETHAmount, "Incorrect pufETH amount");
        assertEq(uint256(withdrawal.pufETHToETHExchangeRate), 1 ether, "Incorrect exchange rate");
        assertEq(withdrawal.recipient, alice, "Incorrect withdrawal recipient");
    }

    /**
     * @dev Test requesting withdrawals with minimum amount
     */
    function test_requestWithdrawal_minAmount() public {
        uint256 minAmount = 0.01 ether;
        _givePufETH(minAmount, alice);

        vm.startPrank(alice);
        pufferVault.approve(address(withdrawalManager), minAmount);
        withdrawalManager.requestWithdrawal(uint128(minAmount), alice);
        vm.stopPrank();

        PufferWithdrawalManagerStorage.Withdrawal memory withdrawal = withdrawalManager.getWithdrawal(batchSize);

        assertEq(uint256(withdrawal.pufETHAmount), minAmount, "Incorrect minimum withdrawal amount");
        assertEq(uint256(withdrawal.pufETHToETHExchangeRate), 1 ether, "Incorrect exchange rate");
        assertEq(withdrawal.recipient, alice, "Incorrect withdrawal recipient");
    }

    /**
     * @dev Test requesting withdrawals below minimum amount
     */
    function test_requestWithdrawal_belowMinAmount() public {
        uint256 belowMinAmount = 0.009 ether;
        address actor = actors[0];
        _givePufETH(belowMinAmount, actor);

        vm.startPrank(actor);
        pufferVault.approve(address(withdrawalManager), belowMinAmount);
        vm.expectRevert(IPufferWithdrawalManager.WithdrawalAmountTooLow.selector);
        withdrawalManager.requestWithdrawal(uint128(belowMinAmount), actor);
    }

    /**
     * @dev Test finalizing withdrawals for multiple batches
     * @dev Remember that Batch Index now starts from 1 and Withdrawals Idx from 10, so adjust accordingly
     */
    function test_finalizeWithdrawals_multipleBatches() public {
        uint256 numBatches = 3;
        uint256 depositAmount = 10 ether;

        for (uint256 i = 0; i < batchSize * numBatches; i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);
            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        vm.prank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(numBatches);

        // Test that withdrawals in finalized batches can be completed
        for (uint256 i = batchSize; i < batchSize * numBatches; i++) {
            vm.prank(actors[i % actors.length]);
            withdrawalManager.completeQueuedWithdrawal(i);
        }

        // Test that the next batch cannot be completed
        vm.expectRevert(IPufferWithdrawalManager.NotFinalized.selector);
        withdrawalManager.completeQueuedWithdrawal(batchSize * (numBatches + 1));
    }

    /**
     * @dev Test finalizing withdrawals with an incomplete batch
     */
    function test_finalizeWithdrawals_incompleteBatch() public {
        uint256 incompleteAmount = 9;
        uint256 depositAmount = 10 ether;

        for (uint256 i = 0; i < incompleteAmount; i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);
            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        vm.startPrank(PAYMASTER);
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.BatchesAreNotFull.selector));
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();
    }

    /**
     * @dev Test completing a queued withdrawal that is not finalized
     */
    function test_completeQueuedWithdrawal_notFinalized() public {
        uint256 depositAmount = 10 ether;

        // Fill the batch
        for (uint256 i = 0; i < batchSize; i++) {
            address actor = actors[i];
            _givePufETH(depositAmount, actor);
            vm.prank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            vm.prank(actor);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
        }

        assertEq(withdrawalManager.getFinalizedWithdrawalBatch(), 0, "finalizedWithdrawalBatch should be 0");

        // Try to complete a withdrawal without finalizing the batch
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.NotFinalized.selector));
        withdrawalManager.completeQueuedWithdrawal(11);

        vm.startPrank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);

        // Now the withdrawal should complete successfully
        uint256 expectedPayoutAmount = depositAmount; // Since the exchange rate is 1:1

        // Complete the withdrawal for the first withdrawal batchSize + 1
        withdrawalManager.completeQueuedWithdrawal(batchSize + 1);
        uint256 balanceAfter = weth.balanceOf(actors[1]);

        // Verify the balance change of the actor after withdrawal
        assertEq(balanceAfter, expectedPayoutAmount, "Incorrect withdrawal amount");

        // Try to complete the same withdrawal again
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.WithdrawalAlreadyCompleted.selector));
        withdrawalManager.completeQueuedWithdrawal(batchSize + 1);
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
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
        }

        assertEq(pufferVault.totalAssets(), 1010 ether, "total assets");

        // deposit 300 to change the exchange rate
        _vtSale(300 ether);

        assertEq(pufferVault.totalAssets(), 1310 ether, "total assets");

        vm.startPrank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        for (uint256 i = 0; i < 10; i++) {
            address actor = actors[i % actors.length];

            vm.startPrank(actor);

            vm.expectEmit(true, true, true, true);

            // since the next batch starts from 10, we need to add 10 to the index
            emit IPufferWithdrawalManager.WithdrawalCompleted(i + 10, depositAmount, 1 ether, actor);
            withdrawalManager.completeQueuedWithdrawal(i + 10);

            // the users did not get any yield from the VT sale, they got paid out using the original 1:1 exchange rate
            assertEq(weth.balanceOf(actor), depositAmount, "actor got paid in ETH");
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
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
        }

        assertEq(pufferVault.totalAssets(), 1010 ether, "total assets");

        // Simulate a slashing, the vault now has 900 ETH instead of 1000
        deal(address(pufferVault), 900 ether);

        assertEq(pufferVault.totalAssets(), 900 ether, "total assets 900");

        // The settlement exchange rate is now lower than the original 1:1 exchange rate
        vm.startPrank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        for (uint256 i = batchSize; i < 10; i++) {
            address actor = actors[i % actors.length];

            vm.startPrank(actor);
            withdrawalManager.completeQueuedWithdrawal(i);

            // the users will get less than 1 ETH because of the slashing
            assertEq(weth.balanceOf(actor), 0.891089108910891089 ether, "actor got paid in ETH");
        }
    }

    function test_constructor() public {
        new PufferWithdrawalManager(10, pufferVault, weth);
    }

    function test_requestWithdrawals() public {
        _givePufETH(1 ether, address(this));

        pufferVault.approve(address(withdrawalManager), 1 ether);
        withdrawalManager.requestWithdrawal(uint128(1 ether), address(this));
    }

    function test_requestWithdrawalsWithPermit() public {
        _givePufETH(1 ether, alice);

        Permit memory permit = _signPermit(
            _testTemps("alice", address(withdrawalManager), 1 ether, block.timestamp), pufferVault.DOMAIN_SEPARATOR()
        );

        vm.prank(alice);
        withdrawalManager.requestWithdrawalWithPermit(permit, alice);

        assertEq(withdrawalManager.getWithdrawal(batchSize).pufETHAmount, 1 ether, "Incorrect pufETH amount");
    }

    function test_requestWithdrawalsWithPermit_ExpiredDeadline() public {
        _givePufETH(1 ether, alice);

        Permit memory permit = _signPermit(
            _testTemps("alice", address(withdrawalManager), 1 ether, block.timestamp), pufferVault.DOMAIN_SEPARATOR()
        );

        vm.warp(block.timestamp + 1 days); // Move time forward to just after the deadline

        vm.prank(alice);
        vm.expectRevert();
        withdrawalManager.requestWithdrawalWithPermit(permit, alice);
    }

    function test_requestWithdrawalsWithPermit_InvalidSignature() public {
        _givePufETH(1 ether, alice);

        Permit memory permit = _signPermit(
            _testTemps("alice", address(withdrawalManager), 1 ether, block.timestamp), pufferVault.DOMAIN_SEPARATOR()
        );

        // corrupt the permit signature
        permit.v = 15;

        vm.prank(alice);
        vm.expectRevert();
        withdrawalManager.requestWithdrawalWithPermit(permit, alice);

        // Assert that no new withdrawal was created
        assertEq(withdrawalManager.getWithdrawal(batchSize).pufETHAmount, 0, "New withdrawal should not be created");
    }

    // Simulates VT sale affects the exchange rate
    function _vtSale(uint256 amount) internal {
        vm.pauseGasMetering();

        vm.deal(address(this), amount);
        vm.startPrank(address(this));
        (bool success,) = payable(address(pufferVault)).call{ value: amount }("");
        require(success, "VT sale failed");
        vm.stopPrank();
    }

    function test_completeQueuedWithdrawal_SecondBatch() public {
        uint256 depositAmount = 10 ether;

        // Fill the first and second batch
        for (uint256 i = 0; i < batchSize * 2; i++) {
            address actor = actors[i % batchSize];
            _givePufETH(depositAmount, actor);
            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        // Finalize only the first batch
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.BatchAlreadyFinalized.selector, (0)));
        vm.startPrank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(0);

        // Try to complete the withdrawal from the second (unfinalized) batch
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.NotFinalized.selector));
        withdrawalManager.completeQueuedWithdrawal(batchSize);

        // Now finalize the second batch
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        // The withdrawal from the second batch should now complete successfully
        uint256 balanceBefore = weth.balanceOf(actors[0]);
        withdrawalManager.completeQueuedWithdrawal(batchSize);
        uint256 balanceAfter = weth.balanceOf(actors[0]);

        // Verify the balance change of the actor after withdrawal
        assertGt(balanceAfter, balanceBefore, "Withdrawal amount should be greater than zero");
    }

    function _givePufETH(uint256 ethAmount, address recipient) internal returns (uint256) {
        vm.deal(address(this), ethAmount);

        vm.startPrank(address(this));
        uint256 pufETHAmount = pufferVault.depositETH{ value: ethAmount }(recipient);
        vm.stopPrank();

        return pufETHAmount;
    }

    function _createDeposit(uint256 ethDepositAmount, address actor) internal {
        uint256 pufETHAmount = _givePufETH(ethDepositAmount, actor);

        vm.startPrank(actor);
        pufferVault.approve(address(withdrawalManager), pufETHAmount);
        withdrawalManager.requestWithdrawal(uint128(pufETHAmount), actor);
        vm.stopPrank();
    }
}
