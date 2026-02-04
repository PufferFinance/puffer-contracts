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
import { IEigenPod, IEigenPodTypes } from "../../src/interface/Eigenlayer-Slashing/IEigenPod.sol";
import { IDelegationManager } from "../../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IBeaconDepositContract } from "../../src/interface/IBeaconDepositContract.sol";
import { IRewardsCoordinator } from "../../src/interface/Eigenlayer-Slashing/IRewardsCoordinator.sol";
import { IGuardianModule } from "../../src/interface/IGuardianModule.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { IPufferOracleV2 } from "../../src/interface/IPufferOracleV2.sol";
import { IPermissionedOracle } from "../../src/interface/IPermissionedOracle.sol";
import { PermissionedValidator } from "../../src/struct/Validator.sol";
import { Status } from "../../src/struct/Status.sol";

import {
    ROLE_ID_DAO,
    ROLE_ID_PERMISSIONED_OPERATOR,
    ROLE_ID_OPERATIONS_PAYMASTER,
    ROLE_ID_PUFFER_PROTOCOL
} from "../../script/Roles.sol";

/**
 * @title PermissionedValidatorForkTest
 * @notice Fork tests for permissioned validator flow using mainnet fork
 * @dev Tests the complete permissioned validator lifecycle mimicking production flow
 *      Uses real EIP-7002 precompile since Pectra is live on mainnet (activated May 7, 2025)
 */
contract PermissionedValidatorForkTest is MainnetForkTestHelper {
    // Mainnet fork block - post-Pectra block (Pectra activated May 7, 2025 at epoch 364032)
    uint256 constant FORK_BLOCK = 24_333_965;

    // EIP-7002 Withdrawal Request Precompile (live on mainnet since Pectra)
    address internal constant WITHDRAWAL_REQUEST_ADDRESS = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

    // Contract instances (in addition to inherited ones)
    PufferProtocol public pufferProtocol;
    PufferModuleManager public pufferModuleManager;
    PermissionedOracle public permissionedOracle;
    UpgradeableBeacon public permissionedModuleBeacon;

    // Test actors
    address permissionedOperator = makeAddr("permissionedOperator");
    address paymaster;
    address dao;

    // Test constants
    bytes32 constant TEST_MODULE_NAME = bytes32("TEST_PERM_MODULE");
    // BLS public key must be exactly 48 bytes = 96 hex characters
    bytes constant TEST_PUBKEY =
        hex"aabbccddee0011223344556677889900aabbccddee0011223344556677889900aabbccddee00112233445566778899aa";
    // BLS signature must be exactly 96 bytes = 192 hex characters
    bytes constant TEST_SIGNATURE =
        hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    function setUp() public override {
        // Create mainnet fork at specific block
        // Try to use MAINNET_RPC_URL environment variable first, fall back to public RPC
        string memory rpcUrl;
        try vm.rpcUrl("mainnet") returns (string memory url) {
            rpcUrl = url;
        } catch {
            // Fallback to PublicNode free RPC (has archive support)
            rpcUrl = "https://ethereum-rpc.publicnode.com";
        }
        vm.createSelectFork(rpcUrl, FORK_BLOCK);

        // Setup live contracts using inherited helper
        _setupLiveContracts();

        // Setup additional contracts from DeployerHelper
        pufferProtocol = PufferProtocol(payable(_getPufferProtocol()));
        pufferModuleManager = PufferModuleManager(payable(_getPufferModuleManager()));
        paymaster = _getPaymaster();
        dao = _getDAO();

        vm.label(address(pufferProtocol), "PufferProtocol");
        vm.label(address(pufferModuleManager), "PufferModuleManager");

        // Deploy and setup permissioned infrastructure
        _deployPermissionedInfrastructure();

        // Setup access control
        _setupAccessControl();

        // Verify EIP-7002 precompile is live
        _verifyWithdrawalRequestPrecompile();
    }

    function _deployPermissionedInfrastructure() internal {
        // Deploy PermissionedOracle (anyone can deploy, access control is set separately)
        permissionedOracle = new PermissionedOracle(_getAccessManager());
        vm.label(address(permissionedOracle), "PermissionedOracle");

        // Deploy PermissionedModule implementation
        PermissionedModule permissionedModuleImpl = new PermissionedModule(
            pufferProtocol,
            _getEigenPodManager(),
            IDelegationManager(_getDelegationManager()),
            pufferModuleManager,
            IRewardsCoordinator(_getRewardsCoordinator()),
            IBeaconDepositContract(_getBeaconDepositContract())
        );
        vm.label(address(permissionedModuleImpl), "PermissionedModuleImpl");

        // Deploy UpgradeableBeacon for PermissionedModule with COMMUNITY_MULTISIG as owner
        vm.prank(COMMUNITY_MULTISIG);
        permissionedModuleBeacon = new UpgradeableBeacon(address(permissionedModuleImpl), COMMUNITY_MULTISIG);
        vm.label(address(permissionedModuleBeacon), "PermissionedModuleBeacon");

        // Deploy new PufferProtocol implementation with PermissionedOracle
        PufferProtocol newProtocolImpl = new PufferProtocol(
            pufferVault,
            IGuardianModule(_getGuardianModule()),
            address(pufferModuleManager),
            ValidatorTicket(_getValidatorTicket()),
            IPufferOracleV2(_getPufferOracle()),
            _getBeaconDepositContract(),
            IPermissionedOracle(address(permissionedOracle))
        );
        vm.label(address(newProtocolImpl), "PufferProtocolNewImpl");

        // Deploy new PufferModuleManager implementation
        PufferModuleManager newModuleManagerImpl =
            new PufferModuleManager(_getPufferModuleBeacon(), _getRestakingOperatorBeacon(), _getPufferProtocol());
        vm.label(address(newModuleManagerImpl), "PufferModuleManagerNewImpl");

        // Execute upgrades through Timelock as COMMUNITY_MULTISIG (instant execution, no delay)
        vm.startPrank(COMMUNITY_MULTISIG);

        bool success;

        // 1. Upgrade PufferProtocol via Timelock
        bytes memory protocolUpgradeCalldata =
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newProtocolImpl), ""));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (_getPufferProtocol(), protocolUpgradeCalldata, 1))
        );
        require(success, "PufferProtocol upgrade failed");

        // 2. Upgrade PufferModuleManager via Timelock
        bytes memory moduleManagerUpgradeCalldata =
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newModuleManagerImpl), ""));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (_getPufferModuleManager(), moduleManagerUpgradeCalldata, 2))
        );
        require(success, "PufferModuleManager upgrade failed");

        // 3. Set permissioned module beacon via Timelock -> AccessManager -> PufferModuleManager
        bytes memory setBeaconCalldata =
            abi.encodeCall(PufferModuleManager.setPermissionedModuleBeacon, (address(permissionedModuleBeacon)));
        // First, grant the DAO role permission to call setPermissionedModuleBeacon
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

        // Now execute setPermissionedModuleBeacon as dao (who has ROLE_ID_DAO)
        vm.prank(dao);
        accessManager.execute(_getPufferModuleManager(), setBeaconCalldata);
    }

    function _setupAccessControl() internal {
        // Execute access control changes through Timelock as COMMUNITY_MULTISIG
        // Community multisig can execute instantly without delay
        vm.startPrank(COMMUNITY_MULTISIG);

        bool success;
        uint256 operationId = 100; // Start from 100 to avoid conflicts with upgrade operations

        bytes4[] memory selectors;

        // Grant ROLE_ID_DAO to dao address for createPermissionedModule
        selectors = new bytes4[](1);
        selectors[0] = PufferProtocol.createPermissionedModule.selector;
        bytes memory callData =
            abi.encodeCall(accessManager.setTargetFunctionRole, (_getPufferProtocol(), selectors, ROLE_ID_DAO));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success, "setTargetFunctionRole for createPermissionedModule failed");

        // Grant dao the DAO role
        callData = abi.encodeCall(accessManager.grantRole, (ROLE_ID_DAO, dao, 0));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success, "grantRole DAO failed");

        // Grant ROLE_ID_PERMISSIONED_OPERATOR to permissionedOperator
        selectors = new bytes4[](1);
        selectors[0] = PufferProtocol.registerPermissionedValidatorKey.selector;
        callData = abi.encodeCall(
            accessManager.setTargetFunctionRole, (_getPufferProtocol(), selectors, ROLE_ID_PERMISSIONED_OPERATOR)
        );
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success, "setTargetFunctionRole for registerPermissionedValidatorKey failed");

        callData = abi.encodeCall(accessManager.grantRole, (ROLE_ID_PERMISSIONED_OPERATOR, permissionedOperator, 0));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success, "grantRole PERMISSIONED_OPERATOR failed");

        // Grant ROLE_ID_OPERATIONS_PAYMASTER to paymaster for PufferProtocol functions
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
        require(success, "setTargetFunctionRole for paymaster protocol functions failed");

        callData = abi.encodeCall(accessManager.grantRole, (ROLE_ID_OPERATIONS_PAYMASTER, paymaster, 0));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success, "grantRole OPERATIONS_PAYMASTER failed");

        // Grant PufferModuleManager functions to paymaster
        bytes4[] memory moduleManagerSelectors = new bytes4[](4);
        moduleManagerSelectors[0] = PufferModuleManager.triggerRestakedValidatorsExit.selector;
        moduleManagerSelectors[1] = PufferModuleManager.triggerNonRestakedValidatorWithdrawals.selector;
        moduleManagerSelectors[2] = PufferModuleManager.withdrawNonRestakedETH.selector;
        moduleManagerSelectors[3] = PufferModuleManager.transferPermissionedModuleETHToVault.selector;
        callData = abi.encodeCall(
            accessManager.setTargetFunctionRole,
            (_getPufferModuleManager(), moduleManagerSelectors, ROLE_ID_OPERATIONS_PAYMASTER)
        );
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success, "setTargetFunctionRole for paymaster module manager functions failed");

        // Grant ROLE_ID_PUFFER_PROTOCOL to PufferProtocol for oracle updates
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
        require(success, "setTargetFunctionRole for oracle failed");

        callData = abi.encodeCall(accessManager.grantRole, (ROLE_ID_PUFFER_PROTOCOL, _getPufferProtocol(), 0));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success, "grantRole PUFFER_PROTOCOL failed");

        vm.stopPrank();
    }

    function _verifyWithdrawalRequestPrecompile() internal view {
        // EIP-7002 Withdrawal Request Precompile is live on mainnet since Pectra (May 7, 2025)
        // Verify the precompile exists at the fork block
        require(
            WITHDRAWAL_REQUEST_ADDRESS.code.length > 0, "EIP-7002 precompile not found - fork block may be pre-Pectra"
        );

        // Log the precompile fee for debugging
        uint256 fee = _getWithdrawalRequestFee();
        console.log("EIP-7002 withdrawal request fee:", fee);
    }

    /**
     * @notice Get the withdrawal request fee from EIP-7002 precompile
     * @return fee The fee per withdrawal request
     */
    function _getWithdrawalRequestFee() internal view returns (uint256 fee) {
        (bool success, bytes memory result) = WITHDRAWAL_REQUEST_ADDRESS.staticcall("");
        require(success && result.length == 32, "Fee query failed");
        return abi.decode(result, (uint256));
    }

    // ============ Test: Module Creation ============

    function test_createPermissionedModule() public {
        vm.prank(dao);
        address moduleAddress = pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        assertTrue(moduleAddress != address(0), "Module should be created");

        // Verify module is stored
        address storedModule = pufferProtocol.getPermissionedModuleAddress(TEST_MODULE_NAME);
        assertEq(storedModule, moduleAddress, "Module address should match");

        // Verify EigenPod was created
        PermissionedModule module = PermissionedModule(payable(moduleAddress));
        address eigenPod = module.getEigenPod();
        assertTrue(eigenPod != address(0), "EigenPod should be created");

        // Verify NonRestakingWithdrawalCredentials was created
        address nrwc = module.getNonRestakingWithdrawalCredentialsContract();
        assertTrue(nrwc != address(0), "NRWC should be created");

        // Verify withdrawal credentials formats
        bytes memory restakingCreds = module.getRestakingWithdrawalCredentials();
        assertEq(restakingCreds[0], bytes1(0x01), "Restaking creds should start with 0x01");

        bytes memory nonRestakingCreds = module.getNonRestakingWithdrawalCredentials();
        assertEq(nonRestakingCreds[0], bytes1(0x02), "Non-restaking creds should start with 0x02");
    }

    function test_createPermissionedModule_revertIfExists() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.prank(dao);
        vm.expectRevert();
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);
    }

    // ============ Test: Validator Registration ============

    function test_registerNonRestakedValidator() public {
        // Create module first
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        // Register non-restaked validator with 100 ETH
        vm.prank(permissionedOperator);
        uint256 index = pufferProtocol.registerPermissionedValidatorKey(
            TEST_PUBKEY,
            TEST_MODULE_NAME,
            true, // isNonRestaked
            100 ether
        );

        assertEq(index, 0, "First validator index should be 0");

        // Verify validator is stored
        PermissionedValidator memory validator = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, index);
        assertEq(validator.node, permissionedOperator, "Node should be operator");
        assertTrue(validator.isNonRestaked, "Should be non-restaked");
        assertEq(validator.stakeAmountGwei, uint64(100 ether / 1 gwei), "Stake amount should be 100 ETH in gwei");
        assertEq(uint8(validator.status), uint8(Status.PENDING), "Status should be PENDING");

        // Verify index incremented
        uint256 pendingIndex = pufferProtocol.getPendingPermissionedValidatorIndex(TEST_MODULE_NAME);
        assertEq(pendingIndex, 1, "Pending index should be 1");
    }

    function test_registerRestakedValidator() public {
        // Create module first
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        // Register restaked validator with 32 ETH
        vm.prank(permissionedOperator);
        uint256 index = pufferProtocol.registerPermissionedValidatorKey(
            TEST_PUBKEY,
            TEST_MODULE_NAME,
            false, // isNonRestaked (restaked)
            32 ether
        );

        assertEq(index, 0, "First validator index should be 0");

        // Verify validator is stored
        PermissionedValidator memory validator = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, index);
        assertEq(validator.node, permissionedOperator, "Node should be operator");
        assertFalse(validator.isNonRestaked, "Should be restaked");
        assertEq(validator.stakeAmountGwei, uint64(32 ether / 1 gwei), "Stake amount should be 32 ETH in gwei");
    }

    function test_registerNonRestakedValidator_variableStakes() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        // Test minimum (32 ETH)
        bytes memory pubkey1 = abi.encodePacked(bytes32(uint256(1)), bytes16(0));
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey1, TEST_MODULE_NAME, true, 32 ether);

        // Test maximum (2048 ETH)
        bytes memory pubkey2 = abi.encodePacked(bytes32(uint256(2)), bytes16(0));
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey2, TEST_MODULE_NAME, true, 2048 ether);

        // Test mid-range (512 ETH)
        bytes memory pubkey3 = abi.encodePacked(bytes32(uint256(3)), bytes16(0));
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey3, TEST_MODULE_NAME, true, 512 ether);

        // Verify all registered
        assertEq(pufferProtocol.getPendingPermissionedValidatorIndex(TEST_MODULE_NAME), 3);
    }

    function test_registerValidator_revertInvalidStake() public {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        // Test below minimum
        vm.prank(permissionedOperator);
        vm.expectRevert();
        pufferProtocol.registerPermissionedValidatorKey(TEST_PUBKEY, TEST_MODULE_NAME, true, 31 ether);

        // Test above maximum for non-restaked
        bytes memory pubkey2 = abi.encodePacked(bytes32(uint256(2)), bytes16(0));
        vm.prank(permissionedOperator);
        vm.expectRevert();
        pufferProtocol.registerPermissionedValidatorKey(pubkey2, TEST_MODULE_NAME, true, 2049 ether);

        // Test non-32 ETH for restaked
        bytes memory pubkey3 = abi.encodePacked(bytes32(uint256(3)), bytes16(0));
        vm.prank(permissionedOperator);
        vm.expectRevert();
        pufferProtocol.registerPermissionedValidatorKey(pubkey3, TEST_MODULE_NAME, false, 64 ether);
    }

    // ============ Test: Validator Provisioning ============

    function test_provisionNonRestakedValidator() public {
        // Setup: Create module and register validator
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.prank(permissionedOperator);
        uint256 index = pufferProtocol.registerPermissionedValidatorKey(
            TEST_PUBKEY,
            TEST_MODULE_NAME,
            true, // isNonRestaked
            100 ether
        );

        // Fund the vault
        vm.deal(address(pufferVault), 200 ether);

        // Get deposit root
        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        // Provision validator
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, index, TEST_SIGNATURE, depositRoot);

        // Verify status changed to ACTIVE
        PermissionedValidator memory validator = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, index);
        assertEq(uint8(validator.status), uint8(Status.ACTIVE), "Status should be ACTIVE");

        // Verify oracle updated
        uint256 lockedEth = permissionedOracle.getModuleLockedEth(TEST_MODULE_NAME);
        assertEq(lockedEth, 100 ether, "Oracle should track 100 ETH");
    }

    function test_provisionRestakedValidator() public {
        // Setup: Create module and register restaked validator
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.prank(permissionedOperator);
        uint256 index = pufferProtocol.registerPermissionedValidatorKey(
            TEST_PUBKEY,
            TEST_MODULE_NAME,
            false, // restaked
            32 ether
        );

        // Fund the vault
        vm.deal(address(pufferVault), 100 ether);

        // Get deposit root
        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        // Provision validator
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, index, TEST_SIGNATURE, depositRoot);

        // Verify status changed to ACTIVE
        PermissionedValidator memory validator = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, index);
        assertEq(uint8(validator.status), uint8(Status.ACTIVE), "Status should be ACTIVE");

        // Verify oracle updated
        uint256 lockedEth = permissionedOracle.getModuleLockedEth(TEST_MODULE_NAME);
        assertEq(lockedEth, 32 ether, "Oracle should track 32 ETH");
    }

    // ============ Test: Non-Restaked Validator Withdrawals ============

    function test_triggerNonRestakedValidatorWithdrawals_fullExit() public {
        // Setup: Create module, register and provision validator
        _setupProvisionedNonRestakedValidator(100 ether);

        address moduleAddress = pufferProtocol.getPermissionedModuleAddress(TEST_MODULE_NAME);
        PermissionedModule module = PermissionedModule(payable(moduleAddress));
        address nrwc = module.getNonRestakingWithdrawalCredentialsContract();

        // Setup NonRestakingWithdrawalCredentials access
        _grantNRWCAccess(nrwc, moduleAddress);

        // Trigger full exit (amountGwei = 0)
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({
            pubkey: TEST_PUBKEY,
            amountGwei: 0 // Full exit
         });

        uint256 fee = _getWithdrawalRequestFee() * requests.length;
        vm.deal(paymaster, fee);

        vm.prank(paymaster);
        pufferModuleManager.triggerNonRestakedValidatorWithdrawals{ value: fee }(moduleAddress, requests);
    }

    function test_triggerNonRestakedValidatorWithdrawals_partialWithdrawal() public {
        // Setup: Create module, register and provision validator with 100 ETH
        _setupProvisionedNonRestakedValidator(100 ether);

        address moduleAddress = pufferProtocol.getPermissionedModuleAddress(TEST_MODULE_NAME);
        PermissionedModule module = PermissionedModule(payable(moduleAddress));
        address nrwc = module.getNonRestakingWithdrawalCredentialsContract();

        // Setup NonRestakingWithdrawalCredentials access
        _grantNRWCAccess(nrwc, moduleAddress);

        // Trigger partial withdrawal of 5 ETH (Pectra feature)
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({
            pubkey: TEST_PUBKEY,
            amountGwei: uint64(5 ether / 1 gwei) // 5 ETH partial withdrawal
         });

        uint256 fee = _getWithdrawalRequestFee() * requests.length;
        vm.deal(paymaster, fee);

        vm.prank(paymaster);
        pufferModuleManager.triggerNonRestakedValidatorWithdrawals{ value: fee }(moduleAddress, requests);
    }

    // ============ Test: Restaked Validator Exit ============

    function test_triggerRestakedValidatorsExit() public {
        // Setup: Create module, register and provision restaked validator
        _setupProvisionedRestakedValidator();

        address moduleAddress = pufferProtocol.getPermissionedModuleAddress(TEST_MODULE_NAME);
        PermissionedModule module = PermissionedModule(payable(moduleAddress));

        // Mock EigenPod withdrawal request
        address eigenPod = module.getEigenPod();
        vm.mockCall(eigenPod, abi.encodeWithSelector(IEigenPod.requestWithdrawal.selector), "");

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = TEST_PUBKEY;

        uint256 fee = _getWithdrawalRequestFee() * pubkeys.length;
        vm.deal(paymaster, fee);

        vm.prank(paymaster);
        pufferModuleManager.triggerRestakedValidatorsExit{ value: fee }(moduleAddress, pubkeys);
    }

    // ============ Test: Withdraw Non-Restaked ETH ============

    function test_withdrawNonRestakedETH() public {
        // Setup: Create module
        vm.prank(dao);
        address moduleAddress = pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        PermissionedModule module = PermissionedModule(payable(moduleAddress));
        address nrwc = module.getNonRestakingWithdrawalCredentialsContract();

        // Simulate beacon chain withdrawal to NRWC
        vm.deal(nrwc, 32 ether);

        uint256 moduleBalanceBefore = moduleAddress.balance;

        // Withdraw ETH from NRWC to module
        vm.prank(paymaster);
        pufferModuleManager.withdrawNonRestakedETH(moduleAddress);

        uint256 moduleBalanceAfter = moduleAddress.balance;
        assertEq(moduleBalanceAfter - moduleBalanceBefore, 32 ether, "Module should receive 32 ETH");
        assertEq(nrwc.balance, 0, "NRWC should be empty");
    }

    // ============ Test: Handle Validator Exit ============

    function test_handlePermissionedValidatorExit() public {
        // Setup: Create module, register and provision validator
        _setupProvisionedNonRestakedValidator(100 ether);

        uint256 oracleLockedBefore = permissionedOracle.totalLockedEth();

        // Handle exit
        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 0, 100 ether);

        // Verify validator data deleted
        PermissionedValidator memory validator = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 0);
        assertEq(validator.node, address(0), "Validator should be deleted");

        // Verify oracle updated
        uint256 oracleLockedAfter = permissionedOracle.totalLockedEth();
        assertEq(oracleLockedBefore - oracleLockedAfter, 100 ether, "Oracle should decrease by 100 ETH");
    }

    // ============ Test: Skip Provisioning ============

    function test_skipPermissionedProvisioning() public {
        // Setup: Create module and register validator
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(TEST_PUBKEY, TEST_MODULE_NAME, true, 100 ether);

        // Skip provisioning
        vm.prank(paymaster);
        pufferProtocol.skipPermissionedProvisioning(TEST_MODULE_NAME, 0);

        // Verify validator data deleted
        PermissionedValidator memory validator = pufferProtocol.getPermissionedValidatorInfo(TEST_MODULE_NAME, 0);
        assertEq(validator.node, address(0), "Validator should be deleted");

        // Verify next to be provisioned index updated
        uint256 nextIndex = pufferProtocol.getNextPermissionedValidatorToBeProvisionedIndex(TEST_MODULE_NAME);
        assertEq(nextIndex, 1, "Next index should be updated");
    }

    // ============ Test: Access Control ============

    function test_accessControl_unauthorized() public {
        address unauthorized = makeAddr("unauthorized");

        // Create module (only DAO)
        vm.prank(unauthorized);
        vm.expectRevert();
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        // First create module with authorized user
        vm.prank(dao);
        address moduleAddress = pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        // Register validator (only permissioned operator)
        vm.prank(unauthorized);
        vm.expectRevert();
        pufferProtocol.registerPermissionedValidatorKey(TEST_PUBKEY, TEST_MODULE_NAME, true, 100 ether);

        // Provision validator (only paymaster)
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(TEST_PUBKEY, TEST_MODULE_NAME, true, 100 ether);

        vm.prank(unauthorized);
        vm.expectRevert();
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, bytes32(0));

        // Trigger withdrawals (only paymaster)
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({ pubkey: TEST_PUBKEY, amountGwei: 0 });

        vm.prank(unauthorized);
        vm.expectRevert();
        pufferModuleManager.triggerNonRestakedValidatorWithdrawals(moduleAddress, requests);
    }

    // ============ Test: Oracle Integration ============

    function test_oracleTracking() public {
        // Setup: Create module
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        // Register and provision multiple validators
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(TEST_PUBKEY, TEST_MODULE_NAME, true, 100 ether);

        bytes memory pubkey2 = abi.encodePacked(bytes32(uint256(2)), bytes16(0));
        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(pubkey2, TEST_MODULE_NAME, true, 200 ether);

        // Fund vault
        vm.deal(address(pufferVault), 500 ether);

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        // Provision first validator
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);

        assertEq(permissionedOracle.totalLockedEth(), 100 ether, "Should track 100 ETH after first provision");
        assertEq(permissionedOracle.getModuleLockedEth(TEST_MODULE_NAME), 100 ether);

        // Update deposit root after first deposit
        depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        // Provision second validator
        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 1, TEST_SIGNATURE, depositRoot);

        assertEq(permissionedOracle.totalLockedEth(), 300 ether, "Should track 300 ETH after second provision");
        assertEq(permissionedOracle.getModuleLockedEth(TEST_MODULE_NAME), 300 ether);

        // Exit first validator
        vm.prank(paymaster);
        pufferProtocol.handlePermissionedValidatorExit(TEST_MODULE_NAME, 0, 100 ether);

        assertEq(permissionedOracle.totalLockedEth(), 200 ether, "Should track 200 ETH after exit");
        assertEq(permissionedOracle.getModuleLockedEth(TEST_MODULE_NAME), 200 ether);
    }

    // ============ Helper Functions ============

    function _setupProvisionedNonRestakedValidator(uint256 stakeAmount) internal {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(
            TEST_PUBKEY,
            TEST_MODULE_NAME,
            true, // isNonRestaked
            stakeAmount
        );

        vm.deal(address(pufferVault), stakeAmount * 2);

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);
    }

    function _setupProvisionedRestakedValidator() internal {
        vm.prank(dao);
        pufferProtocol.createPermissionedModule(TEST_MODULE_NAME);

        vm.prank(permissionedOperator);
        pufferProtocol.registerPermissionedValidatorKey(
            TEST_PUBKEY,
            TEST_MODULE_NAME,
            false, // restaked
            32 ether
        );

        vm.deal(address(pufferVault), 100 ether);

        bytes32 depositRoot = IBeaconDepositContract(_getBeaconDepositContract()).get_deposit_root();

        vm.prank(paymaster);
        pufferProtocol.provisionPermissionedValidator(TEST_MODULE_NAME, 0, TEST_SIGNATURE, depositRoot);
    }

    function _grantNRWCAccess(address nrwc, address moduleAddress) internal {
        // The PermissionedModule calls NonRestakingWithdrawalCredentials.requestWithdrawal
        // So we need to grant the module the permission to call that function
        // Execute through Timelock as COMMUNITY_MULTISIG for production-like flow
        vm.startPrank(COMMUNITY_MULTISIG);

        bool success;
        uint256 operationId = 200; // Use different range to avoid conflicts

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = NonRestakingWithdrawalCredentials.requestWithdrawal.selector;
        bytes memory callData =
            abi.encodeCall(accessManager.setTargetFunctionRole, (nrwc, selectors, ROLE_ID_OPERATIONS_PAYMASTER));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success, "setTargetFunctionRole for NRWC failed");

        // Grant the module the OPERATIONS_PAYMASTER role so it can call requestWithdrawal
        callData = abi.encodeCall(accessManager.grantRole, (ROLE_ID_OPERATIONS_PAYMASTER, moduleAddress, 0));
        (success,) = address(timelock).call(
            abi.encodeCall(Timelock.executeTransaction, (address(accessManager), callData, operationId++))
        );
        require(success, "grantRole to module for NRWC failed");

        vm.stopPrank();
    }
}
