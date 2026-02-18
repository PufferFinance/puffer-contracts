// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { console } from "forge-std/console.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { PermissionedModule } from "../../src/PermissionedModule.sol";
import { PermissionedOracle } from "../../src/PermissionedOracle.sol";
import { NonRestakingWithdrawalCredentials } from "../../src/NonRestakingWithdrawalCredentials.sol";
import { Timelock } from "../../src/Timelock.sol";
import { IDelegationManager } from "../../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IBeaconDepositContract } from "../../src/interface/IBeaconDepositContract.sol";
import { IRewardsCoordinator } from "../../src/interface/Eigenlayer-Slashing/IRewardsCoordinator.sol";
import { IGuardianModule } from "../../src/interface/IGuardianModule.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { IPufferOracleV2 } from "../../src/interface/IPufferOracleV2.sol";
import { IPermissionedOracle } from "../../src/interface/IPermissionedOracle.sol";
import { IPufferProtocol } from "../../src/interface/IPufferProtocol.sol";
import { PermissionedValidator } from "../../src/struct/Validator.sol";
import { Status } from "../../src/struct/Status.sol";

import {
    ROLE_ID_DAO,
    ROLE_ID_PERMISSIONED_OPERATOR,
    ROLE_ID_OPERATIONS_PAYMASTER,
    ROLE_ID_PUFFER_PROTOCOL
} from "../../script/Roles.sol";

/**
 * @title PermissionedValidatorEdgeCaseTest
 * @notice Comprehensive edge case tests for permissioned validator system
 * @dev Tests cover:
 *      - Oracle accounting with slashing and rewards
 *      - Skip provisioning FIFO enforcement
 *      - Mixed provisioning and skipping scenarios
 *      - Index tracking edge cases
 */
contract PermissionedValidatorEdgeCaseTest is MainnetForkTestHelper {
    // Mainnet fork block - post-Pectra
    uint256 constant FORK_BLOCK = 24_333_965;

    // Contract instances
    PufferProtocol public pufferProtocol;
    PufferModuleManager public pufferModuleManager;
    PermissionedOracle public permissionedOracle;
    UpgradeableBeacon public permissionedModuleBeacon;

    // Test actors
    address permissionedOperator = makeAddr("permissionedOperator");
    address paymaster;
    address dao;

    // Test constants
    bytes32 constant TEST_MODULE_NAME = bytes32("TEST_MODULE");
    bytes constant TEST_SIGNATURE =
        hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    function setUp() public override {
        string memory rpcUrl;
        try vm.rpcUrl("mainnet") returns (string memory url) {
            rpcUrl = url;
        } catch {
            rpcUrl = "https://ethereum-rpc.publicnode.com";
        }
        vm.createSelectFork(rpcUrl, FORK_BLOCK);

        _setupLiveContracts();

        pufferProtocol = PufferProtocol(payable(_getPufferProtocol()));
        pufferModuleManager = PufferModuleManager(payable(_getPufferModuleManager()));
        paymaster = _getPaymaster();
        dao = _getDAO();

        _deployPermissionedInfrastructure();
        _setupAccessControl();
    }

    // ============================================================================
    // Oracle Accounting Tests
    // ============================================================================

    /**
     * @notice Verifies oracle correctly accounts for slashing losses
     */
    function test_oracleAccountsForSlashing() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        bytes memory pubkey = _generatePubkey(1);
        uint256 originalStake = 100 ether;

        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, originalStake);

        vm.deal(address(pufferVault), 200 ether);
        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);

        uint256 oracleLockedBefore = permissionedOracle.totalLockedEth();
        assertEq(oracleLockedBefore, originalStake);

        // Slashing scenario: 5 ETH slashed
        uint256 actualWithdrawal = 95 ether;
        uint256 slashingAmount = originalStake - actualWithdrawal;

        // Expect slashing event
        vm.expectEmit(true, true, false, true);
        emit IPufferProtocol.PermissionedValidatorSlashingDetected(
            TEST_MODULE_NAME, 0, originalStake, actualWithdrawal, slashingAmount
        );

        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 0, actualWithdrawal);

        uint256 oracleLockedAfter = permissionedOracle.totalLockedEth();
        assertEq(oracleLockedAfter, 0);
    }

    /**
     * @notice Verifies oracle correctly handles rewards (withdrawal > stake)
     */
    function test_oracleHandlesRewards() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        bytes memory pubkey = _generatePubkey(1);
        uint256 originalStake = 100 ether;

        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, originalStake);

        vm.deal(address(pufferVault), 200 ether);
        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);

        // Rewards scenario: 2 ETH earned
        uint256 actualWithdrawal = 102 ether;

        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 0, actualWithdrawal);

        // Oracle should deduct original stake only
        uint256 oracleLockedAfter = permissionedOracle.totalLockedEth();
        assertEq(oracleLockedAfter, 0);
    }

    /**
     * @notice Verifies cumulative slashing across multiple validators is tracked
     */
    function test_cumulativeSlashingTracking() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), 1000 ether);

        uint256[5] memory stakes = [uint256(100 ether), 200 ether, 150 ether, 300 ether, 250 ether];
        uint256 totalOriginalStake = 0;

        for (uint256 i = 0; i < 5; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, stakes[i]);
            totalOriginalStake += stakes[i];
        }

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(paymaster);
            pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, i, TEST_SIGNATURE, depositRoot);
            depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        }

        assertEq(permissionedOracle.totalLockedEth(), totalOriginalStake);

        // Exit all with 5% slashing
        for (uint256 i = 0; i < 5; i++) {
            uint256 actualWithdrawal = (stakes[i] * 95) / 100;
            vm.prank(paymaster);
            pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, i, actualWithdrawal);
        }

        assertEq(permissionedOracle.totalLockedEth(), 0);
    }

    // ============================================================================
    // Skip Provisioning FIFO Tests
    // ============================================================================

    /**
     * @notice Verifies non-sequential skip reverts with correct error
     */
    function test_nonSequentialSkipReverts() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        for (uint256 i = 0; i < 5; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 32 ether);
        }

        // Try to skip index 2 when next is 0
        vm.prank(paymaster);
        vm.expectRevert(abi.encodeWithSelector(IPufferProtocol.MustSkipNextValidator.selector, 0, 2));
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 2);
    }

    /**
     * @notice Verifies sequential skips work correctly
     */
    function test_sequentialSkipsWork() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        for (uint256 i = 0; i < 5; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 32 ether);
        }

        // Skip 0, 1, 2 sequentially
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(paymaster);
            pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, i);
            assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), i + 1);
        }
    }

    // ============================================================================
    // Mixed Provisioning and Skipping Edge Cases
    // ============================================================================

    /**
     * @notice Tests skip, provision, skip, provision pattern
     */
    function test_alternatingSkipAndProvision() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), 500 ether);

        // Register 6 validators
        for (uint256 i = 0; i < 6; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 32 ether);
        }

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        // Skip 0
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 0);
        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 1);

        // Provision 1
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 1, TEST_SIGNATURE, depositRoot);
        depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        // Skip 2
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 2);
        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 3);

        // Provision 3
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 3, TEST_SIGNATURE, depositRoot);
        depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        // Skip 4
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 4);
        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 5);

        // Provision 5
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 5, TEST_SIGNATURE, depositRoot);

        // Verify final state
        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 6);
        assertEq(permissionedOracle.totalLockedEth(), 96 ether); // 3 validators * 32 ETH

        // Verify skipped validators are deleted
        PermissionedValidator memory v0 = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 0);
        PermissionedValidator memory v2 = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 2);
        PermissionedValidator memory v4 = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 4);
        assertEq(v0.node, address(0));
        assertEq(v2.node, address(0));
        assertEq(v4.node, address(0));

        // Verify provisioned validators are active
        PermissionedValidator memory v1 = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 1);
        PermissionedValidator memory v3 = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 3);
        PermissionedValidator memory v5 = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 5);
        assertEq(uint8(v1.status), uint8(Status.ACTIVE));
        assertEq(uint8(v3.status), uint8(Status.ACTIVE));
        assertEq(uint8(v5.status), uint8(Status.ACTIVE));
    }

    /**
     * @notice Tests multiple consecutive skips followed by provisions
     */
    function test_multipleSkipsThenProvisions() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), 500 ether);

        // Register 8 validators
        for (uint256 i = 0; i < 8; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 32 ether);
        }

        // Skip first 4
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(paymaster);
            pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, i);
        }
        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 4);

        // Provision remaining 4
        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        for (uint256 i = 4; i < 8; i++) {
            vm.prank(paymaster);
            pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, i, TEST_SIGNATURE, depositRoot);
            depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        }

        assertEq(permissionedOracle.totalLockedEth(), 128 ether); // 4 * 32 ETH
        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 8);
    }

    /**
     * @notice Tests provision then exit then new registration
     */
    function test_provisionExitThenNewRegistration() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), 500 ether);

        // Register and provision first validator
        bytes memory pubkey1 = _generatePubkey(1);
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey1, TEST_MODULE_NAME, true, 100 ether);

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);

        assertEq(permissionedOracle.totalLockedEth(), 100 ether);

        // Exit with slashing
        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 0, 95 ether);

        assertEq(permissionedOracle.totalLockedEth(), 0);

        // Register new validator (will be at index 1)
        bytes memory pubkey2 = _generatePubkey(2);
        vm.prank(permissionedOperator);
        uint256 newIndex = pufferProtocol.registerPermissionedValidatorKey(pubkey2, TEST_MODULE_NAME, true, 200 ether);

        assertEq(newIndex, 1);
        assertEq(pufferProtocol.getPendingPermissionedValidatorIndex(TEST_MODULE_NAME), 2);

        // Provision new validator
        depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 1, TEST_SIGNATURE, depositRoot);

        assertEq(permissionedOracle.totalLockedEth(), 200 ether);
    }

    /**
     * @notice Tests skip at boundary (skip the last registered validator)
     */
    function test_skipLastRegisteredValidator() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        // Register single validator
        bytes memory pubkey = _generatePubkey(1);
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 32 ether);

        assertEq(pufferProtocol.getPendingPermissionedValidatorIndex(TEST_MODULE_NAME), 1);
        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 0);

        // Skip it
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 0);

        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 1);

        // Verify deleted
        PermissionedValidator memory v = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 0);
        assertEq(v.node, address(0));
    }

    /**
     * @notice Tests cannot skip already provisioned validator
     */
    function test_cannotSkipProvisionedValidator() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), 200 ether);

        // Register 2 validators
        for (uint256 i = 0; i < 2; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 32 ether);
        }

        // Provision first
        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);

        // Try to skip index 0 (already provisioned) - should fail due to FIFO (next is 1)
        vm.prank(paymaster);
        vm.expectRevert(abi.encodeWithSelector(IPufferProtocol.MustSkipNextValidator.selector, 1, 0));
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 0);
    }

    /**
     * @notice Tests skip after some provisions have been made
     */
    function test_skipAfterPartialProvisioning() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), 500 ether);

        // Register 5 validators
        for (uint256 i = 0; i < 5; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 32 ether);
        }

        // Provision 0, 1, 2
        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(paymaster);
            pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, i, TEST_SIGNATURE, depositRoot);
            depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        }

        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 3);

        // Now skip 3 (next in line)
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 3);

        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 4);

        // Provision 4
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 4, TEST_SIGNATURE, depositRoot);

        assertEq(permissionedOracle.totalLockedEth(), 128 ether); // 4 * 32 ETH
    }

    /**
     * @notice Tests mixed operations across multiple modules
     */
    function test_mixedOperationsMultipleModules() public {
        bytes32 moduleA = bytes32("MODULE_A");
        bytes32 moduleB = bytes32("MODULE_B");

        vm.startPrank(dao);
        pufferProtocol.createPermissionedModule(moduleA);
        pufferProtocol.createPermissionedModule(moduleB);
        vm.stopPrank();

        vm.deal(address(pufferVault), 1000 ether);

        // Register 3 in each module
        for (uint256 i = 0; i < 3; i++) {
            bytes memory pubkeyA = _generatePubkey(i + 1);
            bytes memory pubkeyB = _generatePubkey(i + 100);

            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkeyA, moduleA, true, 100 ether);

            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkeyB, moduleB, true, 50 ether);
        }

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        // Module A: skip 0, provision 1, skip 2
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(moduleA, 0);

        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(moduleA, 1, TEST_SIGNATURE, depositRoot);
        depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(moduleA, 2);

        // Module B: provision all
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(paymaster);
            pufferProtocol.provisionPermissionedValidator(moduleB, i, TEST_SIGNATURE, depositRoot);
            depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        }

        // Verify
        assertEq(permissionedOracle.getModuleLockedEth(moduleA), 100 ether); // 1 * 100
        assertEq(permissionedOracle.getModuleLockedEth(moduleB), 150 ether); // 3 * 50
        assertEq(permissionedOracle.totalLockedEth(), 250 ether);

        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(moduleA), 3);
        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(moduleB), 3);
    }

    /**
     * @notice Tests exit order doesn't affect oracle when validators exit out of order
     */
    function test_outOfOrderExitsOracleAccounting() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), 500 ether);

        uint256[3] memory stakes = [uint256(100 ether), 150 ether, 200 ether];

        for (uint256 i = 0; i < 3; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, stakes[i]);
        }

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(paymaster);
            pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, i, TEST_SIGNATURE, depositRoot);
            depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        }

        assertEq(permissionedOracle.totalLockedEth(), 450 ether);

        // Exit in reverse order: 2, 0, 1
        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 2, 200 ether);
        assertEq(permissionedOracle.totalLockedEth(), 250 ether);

        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 0, 95 ether); // slashed
        assertEq(permissionedOracle.totalLockedEth(), 150 ether);

        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 1, 155 ether); // rewards
        assertEq(permissionedOracle.totalLockedEth(), 0);
    }

    /**
     * @notice Tests registering validators after all previous ones are processed
     */
    function test_registerAfterAllProcessed() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), 1000 ether);

        // First batch: register 2, skip both
        for (uint256 i = 0; i < 2; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 32 ether);
        }

        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 0);
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 1);

        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 2);
        assertEq(pufferProtocol.getPendingPermissionedValidatorIndex(TEST_MODULE_NAME), 2);

        // Second batch: register 2 more
        for (uint256 i = 2; i < 4; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 64 ether);
        }

        assertEq(pufferProtocol.getPendingPermissionedValidatorIndex(TEST_MODULE_NAME), 4);

        // Provision new ones
        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        for (uint256 i = 2; i < 4; i++) {
            vm.prank(paymaster);
            pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, i, TEST_SIGNATURE, depositRoot);
            depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        }

        assertEq(permissionedOracle.totalLockedEth(), 128 ether); // 2 * 64
        assertEq(pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME), 4);
    }

    /**
     * @notice Tests full lifecycle: register, provision, partial withdrawal via slashing, exit
     */
    function test_fullLifecycleWithSlashing() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        // Register with max stake (2048 ETH) - need sufficient vault funds
        bytes memory pubkey = _generatePubkey(1);
        uint256 maxStake = 2048 ether;

        vm.deal(address(pufferVault), maxStake * 2);

        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, maxStake);

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);

        assertEq(permissionedOracle.totalLockedEth(), maxStake);

        // Simulate major slashing (10%)
        uint256 slashingPercent = 10;
        uint256 slashingLoss = (maxStake * slashingPercent) / 100;
        uint256 actualWithdrawal = maxStake - slashingLoss;

        vm.expectEmit(true, true, false, true);
        emit IPufferProtocol.PermissionedValidatorSlashingDetected(
            TEST_MODULE_NAME, 0, maxStake, actualWithdrawal, slashingLoss
        );

        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 0, actualWithdrawal);

        assertEq(permissionedOracle.totalLockedEth(), 0);
    }

    /**
     * @notice Tests that skipping doesn't affect already provisioned validators
     */
    function test_skipDoesNotAffectActiveValidators() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), 500 ether);

        // Register 4 validators
        for (uint256 i = 0; i < 4; i++) {
            bytes memory pubkey = _generatePubkey(i + 1);
            vm.prank(permissionedOperator);
            pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, 32 ether);
        }

        // Provision first 2
        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(paymaster);
            pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, i, TEST_SIGNATURE, depositRoot);
            depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        }

        uint256 oracleBefore = permissionedOracle.totalLockedEth();
        assertEq(oracleBefore, 64 ether);

        // Skip remaining 2
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 2);
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 3);

        // Oracle should be unchanged (skipping doesn't affect locked ETH)
        assertEq(permissionedOracle.totalLockedEth(), oracleBefore);

        // Active validators should still be active
        PermissionedValidator memory v0 = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 0);
        PermissionedValidator memory v1 = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 1);
        assertEq(uint8(v0.status), uint8(Status.ACTIVE));
        assertEq(uint8(v1.status), uint8(Status.ACTIVE));
    }

    // ============================================================================
    // Fuzz Tests
    // ============================================================================

    /**
     * @notice Fuzz test for slashing amounts
     */
    function testFuzz_slashingAmounts(uint256 stakeEther, uint256 slashingPercent) public {
        // Stake must be between 32-2048 ETH in whole ether amounts (gwei divisible)
        stakeEther = bound(stakeEther, 32, 2048);
        uint256 stakeAmount = stakeEther * 1 ether;
        slashingPercent = bound(slashingPercent, 1, 99);

        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), stakeAmount * 2);

        bytes memory pubkey = _generatePubkey(1);
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, stakeAmount);

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);

        uint256 slashingLoss = (stakeAmount * slashingPercent) / 100;
        uint256 actualWithdrawal = stakeAmount - slashingLoss;

        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 0, actualWithdrawal);

        assertEq(permissionedOracle.totalLockedEth(), 0);
    }

    /**
     * @notice Fuzz test for reward amounts
     */
    function testFuzz_rewardAmounts(uint256 stakeEther, uint256 rewardPercent) public {
        // Stake must be between 32-2048 ETH in whole ether amounts (gwei divisible)
        stakeEther = bound(stakeEther, 32, 2048);
        uint256 stakeAmount = stakeEther * 1 ether;
        rewardPercent = bound(rewardPercent, 1, 50); // Up to 50% rewards

        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.deal(address(pufferVault), stakeAmount * 2);

        bytes memory pubkey = _generatePubkey(1);
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey, TEST_MODULE_NAME, true, stakeAmount);

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);

        uint256 rewards = (stakeAmount * rewardPercent) / 100;
        uint256 actualWithdrawal = stakeAmount + rewards;

        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 0, actualWithdrawal);

        assertEq(permissionedOracle.totalLockedEth(), 0);
    }

    // ============================================================================
    // Helper Functions
    // ============================================================================

    function _generatePubkey(uint256 seed) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32(seed), bytes16(0));
    }

    function _deployPermissionedInfrastructure() internal {
        permissionedOracle = new PermissionedOracle(_getAccessManager());
        vm.label(address(permissionedOracle), "PermissionedOracle");

        PermissionedModule permissionedModuleImpl = new PermissionedModule(
            pufferProtocol,
            _getEigenPodManager(),
            IDelegationManager(_getDelegationManager()),
            pufferModuleManager,
            IRewardsCoordinator(_getRewardsCoordinator()),
            IBeaconDepositContract(_getBeaconDepositContract())
        );

        vm.prank(COMMUNITY_MULTISIG);
        permissionedModuleBeacon = new UpgradeableBeacon(address(permissionedModuleImpl), COMMUNITY_MULTISIG);

        PufferProtocol newProtocolImpl = new PufferProtocol(
            pufferVault,
            IGuardianModule(_getGuardianModule()),
            address(pufferModuleManager),
            ValidatorTicket(_getValidatorTicket()),
            IPufferOracleV2(_getPufferOracle()),
            _getBeaconDepositContract(),
            IPermissionedOracle(address(permissionedOracle))
        );

        PufferModuleManager newModuleManagerImpl =
            new PufferModuleManager(_getPufferModuleBeacon(), _getRestakingOperatorBeacon(), _getPufferProtocol());

        vm.startPrank(COMMUNITY_MULTISIG);

        bool success;

        bytes memory protocolUpgradeCalldata =
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newProtocolImpl), ""));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (_getPufferProtocol(), protocolUpgradeCalldata, 1))
        );
        require(success, "PufferProtocol upgrade failed");

        bytes memory moduleManagerUpgradeCalldata =
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newModuleManagerImpl), ""));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (_getPufferModuleManager(), moduleManagerUpgradeCalldata, 2))
        );
        require(success, "PufferModuleManager upgrade failed");

        bytes memory setBeaconCalldata =
            abi.encodeCall(PufferModuleManager.setPermissionedModuleBeacon, (address(permissionedModuleBeacon)));
        bytes4[] memory beaconSelectors = new bytes4[](1);
        beaconSelectors[0] = PufferModuleManager.setPermissionedModuleBeacon.selector;
        bytes memory grantBeaconRoleCalldata = abi.encodeCall(
            accessManager.setTargetFunctionRole, (_getPufferModuleManager(), beaconSelectors, ROLE_ID_DAO)
        );
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), grantBeaconRoleCalldata, 3))
        );
        require(success, "Grant beacon role failed");

        vm.stopPrank();

        vm.prank(dao);
        accessManager.execute(_getPufferModuleManager(), setBeaconCalldata);
    }

    function _setupAccessControl() internal {
        vm.startPrank(COMMUNITY_MULTISIG);

        bool success;
        uint256 operationId = 100;
        bytes4[] memory selectors;

        selectors = new bytes4[](1);
        selectors[0] = PufferProtocol.createPermissionedModule.selector;
        bytes memory callData =
            abi.encodeCall(accessManager.setTargetFunctionRole, (_getPufferProtocol(), selectors, ROLE_ID_DAO));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success);

        callData = abi.encodeCall(accessManager.grantRole, (ROLE_ID_DAO, dao, 0));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success);

        selectors = new bytes4[](1);
        selectors[0] = PufferProtocol.registerPermissionedValidatorKey.selector;
        callData = abi.encodeCall(
            accessManager.setTargetFunctionRole, (_getPufferProtocol(), selectors, ROLE_ID_PERMISSIONED_OPERATOR)
        );
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success);

        callData = abi.encodeCall(accessManager.grantRole, (ROLE_ID_PERMISSIONED_OPERATOR, permissionedOperator, 0));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success);

        selectors = new bytes4[](3);
        selectors[0] = PufferProtocol.provisionPermissionedValidator.selector;
        selectors[1] = PufferProtocol.handlePermissionedValidatorExit.selector;
        selectors[2] = PufferProtocol.skipPermissionedProvisioning.selector;
        callData = abi.encodeCall(
            accessManager.setTargetFunctionRole, (_getPufferProtocol(), selectors, ROLE_ID_OPERATIONS_PAYMASTER)
        );
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success);

        callData = abi.encodeCall(accessManager.grantRole, (ROLE_ID_OPERATIONS_PAYMASTER, paymaster, 0));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success);

        selectors = new bytes4[](3);
        selectors[0] = PermissionedOracle.provisionValidator.selector;
        selectors[1] = PermissionedOracle.exitValidator.selector;
        selectors[2] = PermissionedOracle.adjustLockedEth.selector;
        callData = abi.encodeCall(
            accessManager.setTargetFunctionRole, (address(permissionedOracle), selectors, ROLE_ID_PUFFER_PROTOCOL)
        );
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success);

        callData = abi.encodeCall(accessManager.grantRole, (ROLE_ID_PUFFER_PROTOCOL, _getPufferProtocol(), 0));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success);

        vm.stopPrank();
    }
}
