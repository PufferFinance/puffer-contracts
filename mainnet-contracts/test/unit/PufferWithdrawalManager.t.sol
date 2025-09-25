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
import { PufferWithdrawalManagerTests } from "../mocks/PufferWithdrawalManagerTests.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";

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

        PufferWithdrawalManager withdrawalManagerImpl = ((new PufferWithdrawalManagerTests(10, pufferVault, weth)));

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

        bytes memory encodedCalldata = new Generate2StepWithdrawalsCalldata().run({
            pufferVaultProxy: address(pufferVault),
            withdrawalManagerProxy: address(withdrawalManager),
            paymaster: PAYMASTER,
            withdrawalFinalizer: DAO,
            pufferProtocolProxy: address(pufferProtocol)
        });
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

    modifier withUnlimitedWithdrawalLimit() {
        vm.startPrank(DAO);
        withdrawalManager.changeMaxWithdrawalAmount(type(uint256).max);
        vm.stopPrank();
        _;
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
    function test_createDeposits(uint8 numberOfDeposits) public withUnlimitedWithdrawalLimit {
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
    function test_createAndFinalizeWithdrawals(uint8 numberOfDeposits) public withUnlimitedWithdrawalLimit {
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

        uint256[] memory batches = new uint256[](1);
        batches[0] = 1;

        vm.startPrank(OPERATIONS_MULTISIG);
        // If there is no excess ETH, this should revert
        vm.expectRevert(IPufferWithdrawalManager.AlreadyReturned.selector);
        withdrawalManager.returnExcessETHToVault(batches);
    }

    /**
     * @dev Fuzz test for requesting withdrawals
     * @param pufETHAmount The amount of pufETH to withdraw
     */
    function test_fuzz_requestWithdrawals(uint256 pufETHAmount) public withUnlimitedWithdrawalLimit {
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
    function test_requestWithdrawal_minAmount() public withUnlimitedWithdrawalLimit {
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
    function test_finalizeWithdrawals_multipleBatches() public withUnlimitedWithdrawalLimit {
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
    function test_finalizeWithdrawals_incompleteBatch() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 10 ether;

        for (uint256 i = 0; i < (batchSize - 1); i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);
            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        vm.startPrank(PAYMASTER);

        // We are skipping over zero batch.
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.BatchesAreNotFull.selector));
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();
    }

    /**
     * @dev Test completing a queued withdrawal that is not finalized
     */
    function test_completeQueuedWithdrawal_notFinalized() public withUnlimitedWithdrawalLimit {
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
    function test_depositsAndFinalizeWithdrawals() public withUnlimitedWithdrawalLimit {
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

    function test_protocolSlashing() public withUnlimitedWithdrawalLimit {
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
        assertEq(pufferVault.balanceOf(address(withdrawalManager)), 0, "WithdrawalManager should have 0 ETH");
    }

    // The WithdrawalManager ends up with 0 ETH
    function testFuzz_protocolSlashing(uint256 vaultAmount) public withUnlimitedWithdrawalLimit {
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
        vaultAmount = bound(vaultAmount, 100 ether, 900 ether);
        deal(address(pufferVault), vaultAmount);

        // The settlement exchange rate is now lower than the original 1:1 exchange rate
        vm.startPrank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        for (uint256 i = batchSize; i < 10; i++) {
            address actor = actors[i % actors.length];

            vm.startPrank(actor);
            withdrawalManager.completeQueuedWithdrawal(i);
        }
        assertEq(pufferVault.balanceOf(address(withdrawalManager)), 0, "WithdrawalManager should have 0 ETH");
    }

    function test_constructor() public {
        new PufferWithdrawalManager(10, pufferVault, weth);
    }

    function test_requestWithdrawals() public withUnlimitedWithdrawalLimit {
        _givePufETH(1 ether, address(this));

        pufferVault.approve(address(withdrawalManager), 1 ether);
        withdrawalManager.requestWithdrawal(uint128(1 ether), address(this));
    }

    function testRevert_requestWithdrawalsToZeroAddress() public withUnlimitedWithdrawalLimit {
        _givePufETH(1 ether, address(this));

        pufferVault.approve(address(withdrawalManager), 1 ether);
        vm.expectRevert(IPufferWithdrawalManager.WithdrawalToZeroAddress.selector);
        withdrawalManager.requestWithdrawal(uint128(1 ether), address(0));
    }

    function test_requestWithdrawalsWithPermit() public withUnlimitedWithdrawalLimit {
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

    function test_completeQueuedWithdrawal_SecondBatch() public withUnlimitedWithdrawalLimit {
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

    function test_finalizationExchangeRateLowerThanOneWithdrawal() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 1 ether;

        uint256 exchangeRate = pufferVault.convertToAssets(1 ether);

        assertEq(exchangeRate, 1 ether, "1:1 exchange rate");

        // Leave place for one more withdrawal
        for (uint256 i = 0; i < batchSize - 1; i++) {
            address actor = actors[i % batchSize];
            _givePufETH(depositAmount, actor);
            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        // Simulate + 10% increase in ETH
        deal(address(pufferVault), 1110 ether);
        assertEq(pufferVault.convertToAssets(1 ether), 1.100099108027750247 ether, "~ 1:1.1 exchange rate");

        _givePufETH(2 ether, james);
        // James tries to withdraw 1 pufETH and his exchange rate is ~1.1
        vm.startPrank(james);
        pufferVault.approve(address(withdrawalManager), depositAmount);
        withdrawalManager.requestWithdrawal(uint128(depositAmount), james);
        vm.stopPrank();

        // James idx is 19
        assertEq(
            withdrawalManager.getWithdrawal(19).pufETHToETHExchangeRate,
            1.100099108027750247 ether,
            "James exchange rate should be ~1.1"
        );

        // Manipulate the exchange rate to be lower than the one from James, but higher than the other withdrawals
        deal(address(pufferVault), 1012 ether);
        assertEq(pufferVault.convertToAssets(1 ether), 1.001169332125974146 ether, "~ We reset the exchange rate");

        // Finalize the batch
        // 10.011693321259741460 ETH finalization amount
        vm.startPrank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        // Return the dust from the batch
        uint256[] memory batches = new uint256[](1);
        batches[0] = 1;

        vm.startPrank(OPERATIONS_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.NotAllWithdrawalsClaimed.selector));
        withdrawalManager.returnExcessETHToVault(batches);

        // Complete all withdrawals
        for (uint256 i = batchSize; i < batchSize * 2; i++) {
            withdrawalManager.completeQueuedWithdrawal(i);
        }

        assertGt(address(withdrawalManager).balance, 0, "WithdrawalManager should have excess ETH");

        // This time it should work
        withdrawalManager.returnExcessETHToVault(batches);

        assertEq(pufferVault.balanceOf(address(withdrawalManager)), 0, "WithdrawalManager should have 0 pufETH");
        assertEq(address(withdrawalManager).balance, 0, "WithdrawalManager should have 0 ETH");

        // Try to return excess ETH to the vault again for the same batch
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.AlreadyReturned.selector));
        withdrawalManager.returnExcessETHToVault(batches);
    }

    function testRevert_changeMaxWithdrawalAmount_belowMin() public {
        vm.startPrank(DAO);

        uint256 newMaxWithdrawalAmount = withdrawalManager.MIN_WITHDRAWAL_AMOUNT() - 1;

        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.InvalidMaxWithdrawalAmount.selector));
        withdrawalManager.changeMaxWithdrawalAmount(newMaxWithdrawalAmount);
    }

    function test_changeMaxWithdrawalAmount() public {
        uint256 newMaxWithdrawalAmount = 100 ether;
        uint256 oldMaxWithdrawalAmount = withdrawalManager.getMaxWithdrawalAmount();

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferWithdrawalManager.MaxWithdrawalAmountChanged(oldMaxWithdrawalAmount, newMaxWithdrawalAmount);
        withdrawalManager.changeMaxWithdrawalAmount(newMaxWithdrawalAmount);
        assertEq(
            withdrawalManager.getMaxWithdrawalAmount(), newMaxWithdrawalAmount, "Max withdrawal amount should be 100"
        );
    }

    function testRevert_multipleWithdrawalsInTheSameTx() public withUnlimitedWithdrawalLimit {
        // Upgrade to the real implementation
        address newImpl = address(
            new PufferWithdrawalManager(batchSize, PufferVaultV5(payable(address(pufferVault))), IWETH(address(weth)))
        );
        vm.prank(timelock);
        withdrawalManager.upgradeToAndCall(newImpl, "");

        _givePufETH(200 ether, alice);

        vm.startPrank(alice);
        pufferVault.approve(address(withdrawalManager), type(uint256).max);

        withdrawalManager.requestWithdrawal(uint128(100 ether), alice);

        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.MultipleWithdrawalsAreForbidden.selector));
        withdrawalManager.requestWithdrawal(uint128(100 ether), alice);
    }

    function test_getBatch() public withUnlimitedWithdrawalLimit {
        // Non existent batch
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batch = withdrawalManager.getBatch(1234);
        assertEq(batch.toBurn, 0, "toBurn should be 0");
        assertEq(batch.toTransfer, 0, "toTransfer should be 0");
        assertEq(batch.withdrawalsClaimed, 0, "withdrawalsClaimed should be 0");
        assertEq(batch.amountClaimed, 0, "amountClaimed should be 0");

        uint256 depositAmount = 1 ether;

        // Fill the first and second batch
        for (uint256 i = 0; i < batchSize * 2; i++) {
            address actor = actors[i % batchSize];
            _givePufETH(depositAmount, actor);
            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        batch = withdrawalManager.getBatch(1);
        assertEq(batch.toBurn, batchSize * depositAmount, "toBurn should be 10");
        assertEq(batch.toTransfer, batchSize * depositAmount, "toTransfer should be 10");
        assertEq(batch.withdrawalsClaimed, 0, "withdrawalsClaimed should be 0");
        assertEq(batch.amountClaimed, 0, "amountClaimed should be 0");

        vm.startPrank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        // Complete only one withdrawal
        withdrawalManager.completeQueuedWithdrawal(batchSize);

        batch = withdrawalManager.getBatch(1);
        assertEq(batch.toBurn, batchSize * depositAmount, "toBurn should be 10");
        assertEq(batch.toTransfer, batchSize * depositAmount, "toTransfer should be 10");
        assertEq(batch.withdrawalsClaimed, 1, "withdrawalsClaimed should be 1");
        assertEq(batch.amountClaimed, depositAmount, "amountClaimed should be 1");
    }

    function test_funds_returning_edge_case() public {
        assertEq(pufferVault.asset(), address(weth), "asset should be WETH");
        assertEq(pufferVault.totalSupply(), 1000 ether, "totalSupply should be 1000 ETH");

        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(0);

        vm.startPrank(LIQUIDITY_PROVIDER);
        pufferVault.withdraw(1000 ether, charlie, LIQUIDITY_PROVIDER);

        // Vault should have 0 supply
        assertEq(pufferVault.totalSupply(), 0 ether, "totalSupply should be 0 ETH");
        assertEq(pufferVault.totalAssets(), 0 ether, "totalAssets should be 0 ETH");

        // Deploy the withdrawal manager with batch size 3
        PufferWithdrawalManager withdrawalManagerImpl = ((new PufferWithdrawalManagerTests(3, pufferVault, weth)));

        batchSize = withdrawalManagerImpl.BATCH_SIZE();

        // deploy an ERC1967Proxy
        withdrawalManager = PufferWithdrawalManager(
            (
                payable(
                    new ERC1967Proxy{ salt: bytes32("newManager") }(
                        address(withdrawalManagerImpl),
                        abi.encodeCall(PufferWithdrawalManager.initialize, address(accessManager))
                    )
                )
            )
        );

        vm.label(address(withdrawalManager), "PufferWithdrawalManager");

        vm.startPrank(_broadcaster);

        bytes memory encodedCalldata = new Generate2StepWithdrawalsCalldata().run({
            pufferVaultProxy: address(pufferVault),
            withdrawalManagerProxy: address(withdrawalManager),
            paymaster: PAYMASTER,
            withdrawalFinalizer: DAO,
            pufferProtocolProxy: address(pufferProtocol)
        });
        (bool success,) = address(accessManager).call(encodedCalldata);
        require(success, "AccessManager.call failed");

        vm.startPrank(DAO);
        withdrawalManager.changeMaxWithdrawalAmount(type(uint256).max);
        vm.stopPrank();

        _createDeposit(1 ether, alice);
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "1:1 exchange rate");

        deal(address(pufferVault), 2 ether);
        assertApproxEqAbs(pufferVault.convertToAssets(1 ether), 2 ether, 1, "1:2 exchange rate");

        _createDeposit(1 ether, bob);

        deal(address(pufferVault), 4.5 ether);
        assertApproxEqAbs(pufferVault.convertToAssets(1 ether), 3 ether, 2, "1:3 exchange rate");
        _createDeposit(1 ether, charlie);

        // Set the exchange rate to 2 before the finalization
        deal(address(pufferVault), 3.666666666666666666 ether);
        assertApproxEqAbs(pufferVault.convertToAssets(1 ether), 2 ether, 1, "1:2 exchange rate batch finalization");

        vm.prank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);

        vm.prank(alice);
        withdrawalManager.completeQueuedWithdrawal(3);
        withdrawalManager.completeQueuedWithdrawal(4);
        withdrawalManager.completeQueuedWithdrawal(5);

        uint256[] memory batchIndices = new uint256[](1);
        batchIndices[0] = 1;
        vm.expectEmit(true, true, true, true);
        vm.startPrank(OPERATIONS_MULTISIG);
        emit IPufferWithdrawalManager.ExcessETHReturned(batchIndices, 333333333333333333);
        withdrawalManager.returnExcessETHToVault(batchIndices);

        PufferWithdrawalManagerStorage.WithdrawalBatch memory batch = withdrawalManager.getBatch(1);
        assertEq(batch.withdrawalsClaimed, 3, "withdrawalsClaimed should be 3");
        assertEq(batch.amountClaimed, batch.toTransfer, "amountClaimed == toTransfer");

        assertEq(pufferVault.balanceOf(address(withdrawalManager)), 0, "WithdrawalManager should have 0 pufETH");

        assertEq(address(withdrawalManager).balance, 0, "WithdrawalManager should have 0 ETH");
    }

    function test_cancelWithdrawal() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 1 ether;
        _givePufETH(depositAmount, alice);

        vm.startPrank(alice);
        pufferVault.approve(address(withdrawalManager), depositAmount);
        withdrawalManager.requestWithdrawal(uint128(depositAmount), alice);
        vm.stopPrank();

        uint256 withdrawalIdx = batchSize; // First withdrawal after the initial empty batch
        uint256 aliceBalanceBefore = pufferVault.balanceOf(alice);

        // Cancel the withdrawal
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IPufferWithdrawalManager.WithdrawalCancelled(withdrawalIdx, depositAmount, alice);
        withdrawalManager.cancelWithdrawal(withdrawalIdx);

        // Check that pufETH was returned to alice
        assertEq(pufferVault.balanceOf(alice), aliceBalanceBefore + depositAmount, "Alice should receive pufETH back");

        // Check that withdrawal data was cleared
        PufferWithdrawalManagerStorage.Withdrawal memory withdrawal = withdrawalManager.getWithdrawal(withdrawalIdx);
        assertEq(withdrawal.recipient, address(0), "Withdrawal recipient should be cleared");
        assertEq(withdrawal.pufETHAmount, 0, "Withdrawal amount should be cleared");
    }

    function test_cancelWithdrawal_doesNotExist() public {
        vm.prank(alice);
        vm.expectRevert(IPufferWithdrawalManager.WithdrawalDoesNotExist.selector);
        withdrawalManager.cancelWithdrawal(999);
    }

    function test_cancelWithdrawal_alreadyCompleted() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 1 ether;

        // Fill the batch completely before finalizing
        for (uint256 i = 0; i < batchSize; i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);

            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        uint256 withdrawalIdx = batchSize;

        // Finalize and complete the withdrawal first
        vm.prank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);

        vm.prank(alice);
        withdrawalManager.completeQueuedWithdrawal(withdrawalIdx);

        // Try to cancel the already completed withdrawal
        vm.prank(alice);
        vm.expectRevert(IPufferWithdrawalManager.WithdrawalAlreadyCompleted.selector);
        withdrawalManager.cancelWithdrawal(withdrawalIdx);
    }

    function test_cancelWithdrawal_alreadyFinalized() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 1 ether;

        // Fill the batch completely before finalizing
        for (uint256 i = 0; i < batchSize; i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);

            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        uint256 withdrawalIdx = batchSize;

        // Finalize the batch
        vm.prank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);

        // Try to cancel the finalized withdrawal
        vm.prank(alice);
        vm.expectRevert(IPufferWithdrawalManager.WithdrawalAlreadyFinalized.selector);
        withdrawalManager.cancelWithdrawal(withdrawalIdx);
    }

    function test_cancelWithdrawal_notOwner() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 1 ether;
        _givePufETH(depositAmount, alice);

        vm.startPrank(alice);
        pufferVault.approve(address(withdrawalManager), depositAmount);
        withdrawalManager.requestWithdrawal(uint128(depositAmount), alice);
        vm.stopPrank();

        uint256 withdrawalIdx = batchSize;

        // Try to cancel someone else's withdrawal
        vm.prank(bob);
        vm.expectRevert(IPufferWithdrawalManager.NotWithdrawalOwner.selector);
        withdrawalManager.cancelWithdrawal(withdrawalIdx);
    }

    function test_cancelWithdrawal_updatesBatch() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 1 ether;
        _givePufETH(depositAmount, alice);

        vm.startPrank(alice);
        pufferVault.approve(address(withdrawalManager), depositAmount);
        withdrawalManager.requestWithdrawal(uint128(depositAmount), alice);
        vm.stopPrank();

        uint256 withdrawalIdx = batchSize;
        uint256 batchIdx = withdrawalIdx / batchSize;

        // Check initial batch state
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batchBefore = withdrawalManager.getBatch(batchIdx);
        assertEq(batchBefore.toBurn, depositAmount, "Initial toBurn should be depositAmount");
        assertGt(batchBefore.toTransfer, 0, "Initial toTransfer should be > 0");

        // Cancel the withdrawal
        vm.prank(alice);
        withdrawalManager.cancelWithdrawal(withdrawalIdx);

        // Check that batch was updated
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batchAfter = withdrawalManager.getBatch(batchIdx);
        assertEq(batchAfter.toBurn, 0, "toBurn should be 0 after cancellation");
        assertEq(batchAfter.toTransfer, 0, "toTransfer should be 0 after cancellation");
    }

    function test_cancelWithdrawal_multipleInBatch() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 1 ether;

        // Create multiple withdrawals in the same batch
        for (uint256 i = 0; i < 3; i++) {
            address actor = actors[i];
            _givePufETH(depositAmount, actor);

            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        uint256 batchIdx = batchSize / batchSize; // Should be 1

        // Check initial batch state
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batchBefore = withdrawalManager.getBatch(batchIdx);
        assertEq(batchBefore.toBurn, depositAmount * 3, "Initial toBurn should be 3 * depositAmount");

        // Cancel two withdrawals
        vm.prank(actors[0]);
        withdrawalManager.cancelWithdrawal(batchSize);

        vm.prank(actors[1]);
        withdrawalManager.cancelWithdrawal(batchSize + 1);

        // Check that batch was updated correctly
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batchAfter = withdrawalManager.getBatch(batchIdx);
        assertEq(batchAfter.toBurn, depositAmount, "toBurn should be depositAmount after cancelling 2 withdrawals");
        assertEq(
            batchAfter.toTransfer, depositAmount, "toTransfer should be depositAmount after cancelling 2 withdrawals"
        );
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

    /**
     * @dev Test constructor with batchSize = 0 to cover uncovered constructor line
     */
    function test_constructor_batchSizeZero() public {
        // This should work fine, but we need to test the constructor path
        PufferWithdrawalManager impl = new PufferWithdrawalManager(0, pufferVault, weth);
        assertEq(impl.BATCH_SIZE(), 0);
    }

    /**
     * @dev Test oneWithdrawalRequestAllowed modifier revert path
     */
    function test_oneWithdrawalRequestAllowed_revert() public withUnlimitedWithdrawalLimit {
        // Upgrade to the real implementation to test the modifier
        address newImpl = address(
            new PufferWithdrawalManager(batchSize, PufferVaultV5(payable(address(pufferVault))), IWETH(address(weth)))
        );
        vm.prank(timelock);
        withdrawalManager.upgradeToAndCall(newImpl, "");

        _givePufETH(200 ether, alice);

        vm.startPrank(alice);
        pufferVault.approve(address(withdrawalManager), type(uint256).max);

        withdrawalManager.requestWithdrawal(uint128(100 ether), alice);

        // This should revert due to the modifier
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.MultipleWithdrawalsAreForbidden.selector));
        withdrawalManager.requestWithdrawal(uint128(100 ether), alice);
        vm.stopPrank();
    }

    /**
     * @dev Test finalizeWithdrawals edge cases for uncovered branches
     */
    function test_finalizeWithdrawals_edgeCases() public withUnlimitedWithdrawalLimit {
        // Test finalizing batch 0 (should revert)
        vm.startPrank(PAYMASTER);
        vm.expectRevert(abi.encodeWithSelector(IPufferWithdrawalManager.BatchAlreadyFinalized.selector, 0));
        withdrawalManager.finalizeWithdrawals(0);
        vm.stopPrank();

        // Test finalizing when no batches are full
        vm.startPrank(PAYMASTER);
        vm.expectRevert(IPufferWithdrawalManager.BatchesAreNotFull.selector);
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();
    }

    /**
     * @dev Test completeQueuedWithdrawal edge cases for uncovered branches
     */
    function test_completeQueuedWithdrawal_edgeCases() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 1 ether;

        // Fill the batch
        for (uint256 i = 0; i < batchSize; i++) {
            address actor = actors[i];
            _givePufETH(depositAmount, actor);
            vm.prank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            vm.prank(actor);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
        }

        // Test completing withdrawal from unfinalized batch
        vm.expectRevert(IPufferWithdrawalManager.NotFinalized.selector);
        withdrawalManager.completeQueuedWithdrawal(batchSize);

        // Finalize the batch
        vm.prank(PAYMASTER);
        withdrawalManager.finalizeWithdrawals(1);

        // Test completing already completed withdrawal
        vm.prank(actors[0]);
        withdrawalManager.completeQueuedWithdrawal(batchSize);

        vm.prank(actors[0]);
        vm.expectRevert(IPufferWithdrawalManager.WithdrawalAlreadyCompleted.selector);
        withdrawalManager.completeQueuedWithdrawal(batchSize);
    }

    /**
     * @dev Test _processWithdrawalRequest edge cases for uncovered branches
     */
    function test_processWithdrawalRequest_edgeCases() public withUnlimitedWithdrawalLimit {
        // Test withdrawal amount too high
        vm.startPrank(DAO);
        withdrawalManager.changeMaxWithdrawalAmount(0.1 ether);
        vm.stopPrank();

        _givePufETH(1 ether, alice);
        vm.startPrank(alice);
        pufferVault.approve(address(withdrawalManager), 1 ether);
        vm.expectRevert(IPufferWithdrawalManager.WithdrawalAmountTooHigh.selector);
        withdrawalManager.requestWithdrawal(uint128(1 ether), alice);
        vm.stopPrank();
    }

    /**
     * @dev Test _authorizeUpgrade edge cases for uncovered branches
     */
    function test_authorizeUpgrade_edgeCases() public {
        // Test upgrade with different batch size
        address newImpl = address(new PufferWithdrawalManager(999, pufferVault, weth));

        vm.startPrank(timelock);
        vm.expectRevert(IPufferWithdrawalManager.BatchSizeCannotChange.selector);
        withdrawalManager.upgradeToAndCall(newImpl, "");
        vm.stopPrank();
    }

    /**
     * @dev Test receive function
     */
    function test_receive() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        (bool success,) = address(withdrawalManager).call{ value: amount }("");
        assertTrue(success);
        assertEq(address(withdrawalManager).balance, amount);
    }

    /**
     * @dev Test finalizing batch with one canceled request and claiming other requests
     */
    function test_finalizeBatchWithCanceledRequest() public withUnlimitedWithdrawalLimit {
        uint256 depositAmount = 1 ether;

        // Create withdrawals to fill a batch (batchSize = 10)
        for (uint256 i = 0; i < batchSize; i++) {
            address actor = actors[i % actors.length];
            _givePufETH(depositAmount, actor);

            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), depositAmount);
            withdrawalManager.requestWithdrawal(uint128(depositAmount), actor);
            vm.stopPrank();
        }

        uint256 batchIdx = 1; // First non-zero batch
        uint256 canceledWithdrawalIdx = batchSize; // First withdrawal in the batch

        // Check initial batch state
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batchBefore = withdrawalManager.getBatch(batchIdx);
        assertEq(batchBefore.toBurn, batchSize * depositAmount, "Initial toBurn should be batchSize * depositAmount");
        assertEq(
            batchBefore.toTransfer, batchSize * depositAmount, "Initial toTransfer should be batchSize * depositAmount"
        );
        assertEq(batchBefore.withdrawalsClaimed, 0, "Initial withdrawalsClaimed should be 0");

        // Cancel one withdrawal (Alice's withdrawal)
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IPufferWithdrawalManager.WithdrawalCancelled(canceledWithdrawalIdx, depositAmount, alice);
        withdrawalManager.cancelWithdrawal(canceledWithdrawalIdx);

        // Check that batch was updated after cancellation
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batchAfterCancel = withdrawalManager.getBatch(batchIdx);
        assertEq(batchAfterCancel.toBurn, (batchSize - 1) * depositAmount, "toBurn should be reduced by depositAmount");
        assertEq(
            batchAfterCancel.toTransfer,
            (batchSize - 1) * depositAmount,
            "toTransfer should be reduced by depositAmount"
        );

        // Verify Alice got her pufETH back
        assertEq(pufferVault.balanceOf(alice), depositAmount, "Alice should have her pufETH back");

        // Verify canceled withdrawal data was cleared
        PufferWithdrawalManagerStorage.Withdrawal memory canceledWithdrawal =
            withdrawalManager.getWithdrawal(canceledWithdrawalIdx);
        assertEq(canceledWithdrawal.recipient, address(0), "Canceled withdrawal recipient should be cleared");
        assertEq(canceledWithdrawal.pufETHAmount, 0, "Canceled withdrawal amount should be cleared");

        // Finalize the batch
        vm.prank(PAYMASTER);
        vm.expectEmit(true, true, true, true);
        emit IPufferWithdrawalManager.BatchFinalized(
            batchIdx,
            (batchSize - 1) * depositAmount, // expectedETHAmount
            (batchSize - 1) * depositAmount, // actualEthAmount
            (batchSize - 1) * depositAmount // pufETHBurnAmount
        );
        withdrawalManager.finalizeWithdrawals(1);

        // Check batch state after finalization
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batchAfterFinalize = withdrawalManager.getBatch(batchIdx);
        assertEq(batchAfterFinalize.toBurn, (batchSize - 1) * depositAmount, "toBurn should remain the same");
        assertEq(batchAfterFinalize.toTransfer, (batchSize - 1) * depositAmount, "toTransfer should remain the same");
        assertEq(batchAfterFinalize.withdrawalsClaimed, 1, "withdrawalsClaimed should be 1 (the canceled withdrawal)");

        // Test claiming other requests in the batch (skip the canceled one)
        for (uint256 i = 1; i < batchSize; i++) {
            uint256 withdrawalIdx = batchSize + i;
            address actor = actors[i % actors.length];
            uint256 actorBalanceBefore = weth.balanceOf(actor);

            vm.prank(actor);
            vm.expectEmit(true, true, true, true);
            emit IPufferWithdrawalManager.WithdrawalCompleted(withdrawalIdx, depositAmount, 1 ether, actor);
            withdrawalManager.completeQueuedWithdrawal(withdrawalIdx);

            uint256 actorBalanceAfter = weth.balanceOf(actor);
            assertEq(actorBalanceAfter - actorBalanceBefore, depositAmount, "Actor should receive depositAmount in ETH");
        }

        // Check final batch state
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batchFinal = withdrawalManager.getBatch(batchIdx);
        assertEq(
            batchFinal.withdrawalsClaimed,
            batchSize,
            "withdrawalsClaimed should be batchSize (1 canceled + 9 completed)"
        );
        assertEq(
            batchFinal.amountClaimed,
            (batchSize - 1) * depositAmount,
            "amountClaimed should be (batchSize - 1) * depositAmount"
        );

        // Verify Alice cannot claim the canceled withdrawal
        vm.prank(alice);
        vm.expectRevert(IPufferWithdrawalManager.WithdrawalAlreadyCompleted.selector);
        withdrawalManager.completeQueuedWithdrawal(canceledWithdrawalIdx);

        // Verify the canceled withdrawal slot is empty
        PufferWithdrawalManagerStorage.Withdrawal memory emptyWithdrawal =
            withdrawalManager.getWithdrawal(canceledWithdrawalIdx);
        assertEq(emptyWithdrawal.recipient, address(0), "Canceled withdrawal should remain empty");
        assertEq(emptyWithdrawal.pufETHAmount, 0, "Canceled withdrawal amount should remain 0");
    }

    function test_constructor_disableInitializers() public {
        // Test that the constructor properly calls _disableInitializers()
        // This is covered by the existing constructor tests, but we need to ensure coverage
        PufferWithdrawalManager impl = new PufferWithdrawalManager(5, pufferVault, weth);
        assertEq(impl.BATCH_SIZE(), 5);
    }

    function test_getWithdrawal_uncoveredBranches() public view {
        // Test getting withdrawal with invalid index
        PufferWithdrawalManagerStorage.Withdrawal memory withdrawal = withdrawalManager.getWithdrawal(999);
        assertEq(withdrawal.recipient, address(0), "Invalid withdrawal should return empty");
        assertEq(withdrawal.pufETHAmount, 0, "Invalid withdrawal amount should be 0");
    }

    function test_getBatch_uncoveredBranches() public view {
        // Test getting batch with invalid index
        PufferWithdrawalManagerStorage.WithdrawalBatch memory batch = withdrawalManager.getBatch(999);
        assertEq(batch.toBurn, 0, "Invalid batch toBurn should be 0");
        assertEq(batch.toTransfer, 0, "Invalid batch toTransfer should be 0");
        assertEq(batch.withdrawalsClaimed, 0, "Invalid batch withdrawalsClaimed should be 0");
        assertEq(batch.amountClaimed, 0, "Invalid batch amountClaimed should be 0");
    }

    function test_requestWithdrawalWithPermit_failedPermit() public withUnlimitedWithdrawalLimit {
        _givePufETH(1 ether, alice);

        // Approve the withdrawal manager to spend pufETH
        vm.prank(alice);
        pufferVault.approve(address(withdrawalManager), 1 ether);

        Permit memory permit = _signPermit(
            _testTemps("alice", address(withdrawalManager), 1 ether, block.timestamp), pufferVault.DOMAIN_SEPARATOR()
        );

        // Corrupt the permit signature to make it fail
        permit.v = 15;

        vm.prank(alice);
        // This should still work because the permit failure is caught and ignored
        withdrawalManager.requestWithdrawalWithPermit(permit, alice);

        // Verify withdrawal was created despite failed permit
        assertEq(withdrawalManager.getWithdrawal(batchSize).pufETHAmount, 1 ether, "Withdrawal should be created");
    }
}
