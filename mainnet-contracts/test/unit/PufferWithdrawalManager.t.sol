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
import { PufferVaultV3 } from "../../src/PufferVaultV3.sol";
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
            new PufferWithdrawalManager(batchSize, PufferVaultV3(payable(address(pufferVault))), IWETH(address(weth)))
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
        assertEq(pufferVault.totalSupply(), 1000 ether, "totalSupply should be 1000 ETH");

        vm.startPrank(address(DAO));
        pufferVault.setDailyWithdrawalLimit(type(uint96).max);
        vm.startPrank(address(timelock));
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
