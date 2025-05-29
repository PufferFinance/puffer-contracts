// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferProtocolMockUpgrade } from "../mocks/PufferProtocolMockUpgrade.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IPufferProtocol } from "../../src/interface/IPufferProtocol.sol";
import { ValidatorKeyData } from "../../src/struct/ValidatorKeyData.sol";
import { Status } from "../../src/struct/Status.sol";
import { Validator } from "../../src/struct/Validator.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { PufferModule } from "../../src/PufferModule.sol";
import { PufferRevenueDepositor } from "../../src/PufferRevenueDepositor.sol";
import {
    ROLE_ID_DAO,
    ROLE_ID_OPERATIONS_PAYMASTER,
    ROLE_ID_OPERATIONS_MULTISIG,
    ROLE_ID_OPERATIONS_COORDINATOR,
    ROLE_ID_REVENUE_DEPOSITOR
} from "../../script/Roles.sol";
import { LibGuardianMessages } from "../../src/LibGuardianMessages.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { ModuleLimit } from "../../src/struct/ProtocolStorage.sol";
import { StoppedValidatorInfo } from "../../src/struct/StoppedValidatorInfo.sol";
import { NodeInfo } from "../../src/struct/NodeInfo.sol";

contract PufferProtocolTest is UnitTestHelper {
    using ECDSA for bytes32;

    /**
     * @dev New bond is reduced from 2 to 1.5 ETH
     */
    uint256 BOND = 1.5 ether;
    /**
     * @dev Minimum validation time in epochs
     * Roughly: 30 days * 225 epochs per day = 6750 epochs
     */
    uint256 internal constant MINIMUM_EPOCHS_VALIDATION = 6750;

    // Eth has rougly 225 epochs per day
    uint256 internal constant EPOCHS_PER_DAY = 225;

    // 1 VT is burned per 225 epochs
    uint256 internal constant BURN_RATE_PER_EPOCH = 4444444444444445;

    event ValidatorKeyRegistered(bytes pubKey, uint256 indexed, bytes32 indexed);
    event SuccessfullyProvisioned(bytes pubKey, uint256 indexed, bytes32 indexed);
    event ModuleWeightsChanged(bytes32[] oldWeights, bytes32[] newWeights);

    bytes zeroPubKey = new bytes(48);
    bytes32 zeroPubKeyPart;

    bytes32 constant EIGEN_DA = bytes32("EIGEN_DA");
    bytes32 constant CRAZY_GAINS = bytes32("CRAZY_GAINS");
    bytes32 constant DEFAULT_DEPOSIT_ROOT = bytes32("depositRoot");

    Permit emptyPermit;

    // 0.01 %
    uint256 pointZeroZeroOne = 0.0001e18;
    // 0.02 %
    uint256 pointZeroZeroTwo = 0.0002e18;
    // 0.05 %
    uint256 pointZeroFive = 0.0005e18;
    // 0.1% diff
    uint256 pointZeroOne = 0.001e18;

    address NoRestakingModule;
    address eigenDaModule;

    address eve = makeAddr("eve");

    function setUp() public override {
        super.setUp();

        vm.deal(address(this), 1000 ether);

        vm.label(address(revenueDepositor), "RevenueDepositorProxy");

        // Setup roles
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PufferProtocol.createPufferModule.selector;
        selectors[1] = PufferProtocol.setModuleWeights.selector;
        selectors[2] = bytes4(hex"4f1ef286"); // signature for UUPS.upgradeToAndCall(address newImplementation, bytes memory data)

        // For simplicity grant DAO & Paymaster roles to this contract
        vm.startPrank(_broadcaster);
        accessManager.setTargetFunctionRole(address(pufferProtocol), selectors, ROLE_ID_DAO);
        accessManager.grantRole(ROLE_ID_DAO, address(this), 0);
        accessManager.grantRole(ROLE_ID_OPERATIONS_MULTISIG, address(this), 0);
        accessManager.grantRole(ROLE_ID_OPERATIONS_PAYMASTER, address(this), 0);
        accessManager.grantRole(ROLE_ID_OPERATIONS_MULTISIG, address(this), 0);
        accessManager.grantRole(ROLE_ID_OPERATIONS_COORDINATOR, address(this), 0);

        // Grant revenue depositor roles to this contract for simplicity
        bytes4[] memory revenueDepositorRole = new bytes4[](2);
        revenueDepositorRole[0] = PufferRevenueDepositor.depositRevenue.selector;
        revenueDepositorRole[1] = PufferRevenueDepositor.setRewardsDistributionWindow.selector;
        accessManager.setTargetFunctionRole(address(revenueDepositor), revenueDepositorRole, ROLE_ID_REVENUE_DEPOSITOR);
        accessManager.grantRole(ROLE_ID_REVENUE_DEPOSITOR, address(this), 0);

        vm.stopPrank();

        revenueDepositor.setRewardsDistributionWindow(0);

        _skipDefaultFuzzAddresses();

        fuzzedAddressMapping[address(pufferProtocol)] = true;

        NoRestakingModule = pufferProtocol.getModuleAddress(PUFFER_MODULE_0);
        // Fund no restaking module with 200 ETH
        vm.deal(NoRestakingModule, 200 ether);
    }

    // Setup
    function test_setup() public view {
        assertTrue(address(pufferProtocol.PUFFER_VAULT()) != address(0), "puffer vault address");
        assertTrue(
            address(pufferProtocol.PUFFER_REVENUE_DISTRIBUTOR()) != address(0), "puffer revenue distributor address"
        );
        address module = pufferProtocol.getModuleAddress(PUFFER_MODULE_0);
        assertEq(PufferModule(payable(module)).NAME(), PUFFER_MODULE_0, "bad name");
    }

    // Register validator key
    function test_register_validator_key() public {
        _registerValidatorKey(address(this), bytes32("alice"), PUFFER_MODULE_0, 0);

        NodeInfo memory nodeInfo = pufferProtocol.getNodeInfo(address(this));
        assertEq(nodeInfo.activeValidatorCount, 0);
        assertEq(nodeInfo.pendingValidatorCount, 1);
        assertEq(nodeInfo.deprecated_vtBalance, 0);
        assertEq(nodeInfo.validationTime, (30 * EPOCHS_PER_DAY * pufferOracle.getValidatorTicketPrice())); // 30 days of VT
        assertEq(nodeInfo.epochPrice, 9803921568628); // VT Price per epoch
        assertEq(nodeInfo.totalEpochsValidated, 0);
    }

    // Empty queue should return NO_VALIDATORS
    function test_empty_queue() public view {
        (bytes32 moduleName, uint256 idx) = pufferProtocol.getNextValidatorToProvision();
        assertEq(moduleName, bytes32("NO_VALIDATORS"), "name");
        assertEq(idx, type(uint256).max, "name");
    }

    // Test Skipping the validator
    function test_skip_provisioning() public {
        _registerValidatorKey(address(this), bytes32("alice"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(address(this), bytes32("bob"), PUFFER_MODULE_0, 0);

        (bytes32 moduleName, uint256 idx) = pufferProtocol.getNextValidatorToProvision();
        uint256 moduleSelectionIndex = pufferProtocol.getModuleSelectIndex();

        assertEq(moduleName, PUFFER_MODULE_0, "module");
        assertEq(idx, 0, "idx");
        assertEq(moduleSelectionIndex, 0, "module selection idx");

        assertTrue(pufferVault.balanceOf(address(this)) == 0, "zero pufETH");

        ModuleLimit memory moduleLimit = pufferProtocol.getModuleLimitInformation(PUFFER_MODULE_0);

        assertEq(moduleLimit.numberOfRegisteredValidators, 2, "2 active validators");

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorSkipped(_getPubKey(bytes32("alice")), 0, PUFFER_MODULE_0);
        pufferProtocol.skipProvisioning(PUFFER_MODULE_0, _getGuardianSignaturesForSkipping());

        moduleLimit = pufferProtocol.getModuleLimitInformation(PUFFER_MODULE_0);

        assertEq(moduleLimit.numberOfRegisteredValidators, 1, "1 active validator");

        // This contract should receive pufETH because of the skipProvisioning
        assertTrue(pufferVault.balanceOf(address(this)) != 0, "non zero pufETH");

        Validator memory aliceValidator = pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 0);
        assertTrue(aliceValidator.status == Status.SKIPPED, "did not update status");

        (moduleName, idx) = pufferProtocol.getNextValidatorToProvision();

        assertEq(moduleName, PUFFER_MODULE_0, "module");
        assertEq(idx, 1, "idx should be 1");

        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(_getPubKey(bytes32("bob")), 1, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);
        moduleSelectionIndex = pufferProtocol.getModuleSelectIndex();
        assertEq(moduleSelectionIndex, 1, "module idx changed");
    }

    // Create an existing module should revert
    function test_create_existing_module_fails() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferProtocol.ModuleAlreadyExists.selector);
        pufferProtocol.createPufferModule(PUFFER_MODULE_0);
    }

    // Try registering with invalid module
    function test_register_to_invalid_module() public {
        uint256 smoothingCommitment = pufferOracle.getValidatorTicketPrice() * 30;
        bytes memory pubKey = _getPubKey(bytes32("charlie"));
        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);
        vm.expectRevert(IPufferProtocol.ValidatorLimitForModuleReached.selector);
        pufferProtocol.registerValidatorKey{ value: smoothingCommitment }(
            validatorKeyData, bytes32("imaginary module"), 0, new bytes[](0)
        );
    }

    // Mint non whole vt after registration
    function test_register_with_non_whole_amount() public {
        bytes memory pubKey = _getPubKey(bytes32("charlie"));
        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);
        uint256 amount = 5.11 ether;

        pufferProtocol.registerValidatorKey{ value: amount }(validatorKeyData, PUFFER_MODULE_0, 0, new bytes[](0));

        assertEq(
            address(pufferProtocol).balance,
            amount - 1.5 ether,
            "protocol has the eth amount for VT, the bond is converted to pufETH"
        );
    }

    // Set validator limit and try registering that many validators
    function test_fuzz_register_many_validators(uint8 numberOfValidatorsToProvision) external {
        for (uint256 i = 0; i < uint256(numberOfValidatorsToProvision); ++i) {
            vm.deal(address(this), 3 ether);
            _registerValidatorKey(address(this), bytes32(i), PUFFER_MODULE_0, 0);
        }
    }

    // Try registering without RAVE evidence
    function test_register_no_sgx() public {
        uint256 vtPrice = pufferOracle.getValidatorTicketPrice() * 30;

        bytes memory pubKey = _getPubKey(bytes32("something"));

        bytes[] memory newSetOfPubKeys = new bytes[](3);

        // we have 3 guardians in TestHelper.sol
        newSetOfPubKeys[0] = bytes("key1");
        newSetOfPubKeys[0] = bytes("key2");
        newSetOfPubKeys[0] = bytes("key3");

        ValidatorKeyData memory validatorData = ValidatorKeyData({
            blsPubKey: pubKey, // key length must be 48 byte
            signature: new bytes(0),
            depositDataRoot: bytes32(""),
            deprecated_blsEncryptedPrivKeyShares: new bytes[](3),
            deprecated_blsPubKeySet: new bytes(48),
            deprecated_raveEvidence: new bytes(0)
        });

        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0);
        pufferProtocol.registerValidatorKey{ value: vtPrice + 2 ether }(
            validatorData, PUFFER_MODULE_0, 0, new bytes[](0)
        );
    }

    // Try registering with invalid BLS key length
    function test_register_invalid_bls_key() public {
        uint256 smoothingCommitment = pufferOracle.getValidatorTicketPrice();

        bytes[] memory newSetOfPubKeys = new bytes[](3);

        // we have 3 guardians in TestHelper.sol
        newSetOfPubKeys[0] = bytes("key1");
        newSetOfPubKeys[0] = bytes("key2");
        newSetOfPubKeys[0] = bytes("key3");

        ValidatorKeyData memory validatorData = ValidatorKeyData({
            blsPubKey: hex"aeaa", // invalid key
            signature: new bytes(0),
            depositDataRoot: bytes32(""),
            deprecated_blsEncryptedPrivKeyShares: new bytes[](3),
            deprecated_blsPubKeySet: new bytes(48),
            deprecated_raveEvidence: new bytes(0)
        });

        vm.expectRevert(IPufferProtocol.InvalidBLSPubKey.selector);
        pufferProtocol.registerValidatorKey{ value: smoothingCommitment }(
            validatorData, PUFFER_MODULE_0, 0, new bytes[](0)
        );
    }

    // Try to provision a validator when there is nothing to provision
    function test_provision_reverts() public {
        (, uint256 idx) = pufferProtocol.getNextValidatorToProvision();
        assertEq(type(uint256).max, idx, "module");

        vm.expectRevert(); // panic
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);
    }

    // If the deposit root is not bytes(0), it must match match the one returned from the beacon contract
    function test_provision_bad_deposit_hash() public {
        _registerValidatorKey(address(this), zeroPubKeyPart, PUFFER_MODULE_0, 0);

        bytes memory validatorSignature = _validatorSignature();

        vm.expectRevert(IPufferProtocol.InvalidDepositRootHash.selector);
        pufferProtocol.provisionNode(validatorSignature, bytes32("badDepositRoot")); // "depositRoot" is hardcoded in the mock

        // now it works
        pufferProtocol.provisionNode(validatorSignature, DEFAULT_DEPOSIT_ROOT);
    }

    function test_register_multiple_validators_and_skipProvisioning(bytes32 alicePubKeyPart, bytes32 bobPubKeyPart)
        public
    {
        vm.deal(bob, 10 ether);

        vm.deal(alice, 10 ether);

        bytes memory bobPubKey = _getPubKey(bobPubKeyPart);

        // 1. validator
        _registerValidatorKey(address(this), zeroPubKeyPart, PUFFER_MODULE_0, 0);

        Validator memory validator = pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 0);
        assertTrue(validator.node == address(this), "node operator");
        assertTrue(keccak256(validator.pubKey) == keccak256(zeroPubKey), "bad pubkey");

        // 2. validator
        vm.startPrank(bob);
        _registerValidatorKey(bob, bobPubKeyPart, PUFFER_MODULE_0, 0);
        vm.stopPrank();

        // 3. validator
        vm.startPrank(alice);
        _registerValidatorKey(alice, alicePubKeyPart, PUFFER_MODULE_0, 0);
        vm.stopPrank();

        // 4. validator
        _registerValidatorKey(alice, zeroPubKeyPart, PUFFER_MODULE_0, 0);

        // 5. Validator
        _registerValidatorKey(alice, zeroPubKeyPart, PUFFER_MODULE_0, 0);

        assertEq(pufferProtocol.getPendingValidatorIndex(PUFFER_MODULE_0), 5, "next pending validator index");

        // 1. provision zero key
        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(zeroPubKey, 0, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        // Provision Bob that is not zero pubKey
        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(bobPubKey, 1, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        Validator memory bobValidator = pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 1);

        assertTrue(bobValidator.status == Status.ACTIVE, "bob should be active");

        pufferProtocol.skipProvisioning(PUFFER_MODULE_0, _getGuardianSignaturesForSkipping());

        emit SuccessfullyProvisioned(zeroPubKey, 3, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        // Get validators
        Validator[] memory registeredValidators = pufferProtocol.getValidators(PUFFER_MODULE_0);
        assertEq(registeredValidators.length, 5, "5 registered validators");
        assertEq(registeredValidators[0].node, address(this), "this contract should be the first one");
        assertEq(registeredValidators[1].node, bob, "bob should be the second one");
        assertEq(registeredValidators[2].node, alice, "alice should be the third one");
        assertEq(registeredValidators[3].node, address(this), "this contract should should be the fourth one");
        assertEq(registeredValidators[4].node, address(this), "this contract should should be the fifth one");
    }

    function test_provision_node() public {
        pufferProtocol.createPufferModule(EIGEN_DA);
        pufferProtocol.createPufferModule(CRAZY_GAINS);

        bytes32[] memory oldWeights = new bytes32[](3);
        oldWeights[0] = PUFFER_MODULE_0;
        oldWeights[1] = EIGEN_DA;
        oldWeights[2] = CRAZY_GAINS;

        bytes32[] memory newWeights = new bytes32[](4);
        newWeights[0] = PUFFER_MODULE_0;
        newWeights[1] = EIGEN_DA;
        newWeights[2] = EIGEN_DA;
        newWeights[3] = CRAZY_GAINS;

        vm.expectEmit(true, true, true, true);
        emit ModuleWeightsChanged(oldWeights, newWeights);
        pufferProtocol.setModuleWeights(newWeights);

        vm.deal(address(pufferVault), 10000 ether);

        _registerValidatorKey(address(this), bytes32("bob"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(address(this), bytes32("alice"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(address(this), bytes32("charlie"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(address(this), bytes32("david"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(address(this), bytes32("emma"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(address(this), bytes32("benjamin"), EIGEN_DA, 0);
        _registerValidatorKey(address(this), bytes32("rocky"), CRAZY_GAINS, 0);

        (bytes32 nextModule, uint256 nextId) = pufferProtocol.getNextValidatorToProvision();

        assertTrue(nextModule == PUFFER_MODULE_0, "module selection");
        assertTrue(nextId == 0, "module selection");

        // Provision Bob that is not zero pubKey
        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(_getPubKey(bytes32("bob")), 0, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        assertTrue(nextModule == EIGEN_DA, "module selection");
        // Id is zero, because that is the first in this queue
        assertTrue(nextId == 0, "module id");

        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(_getPubKey(bytes32("benjamin")), 0, EIGEN_DA);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        // // Because the EIGEN_DA queue is empty, the next for provisioning is from CRAZY_GAINS
        assertTrue(nextModule == CRAZY_GAINS, "module selection");
        assertTrue(nextId == 0, "module id");

        vm.stopPrank();

        // Now jason registers to EIGEN_DA
        _registerValidatorKey(address(this), bytes32("jason"), EIGEN_DA, 0);

        // If we query next validator, it should switch back to EIGEN_DA (because of the weighted selection)
        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        assertTrue(nextModule == EIGEN_DA, "module selection");
        assertTrue(nextId == 1, "module id");

        // Provision Jason
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        // Rocky is now in line
        assertTrue(nextModule == CRAZY_GAINS, "module selection");
        assertTrue(nextId == 0, "module id");
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        assertTrue(nextModule == PUFFER_MODULE_0, "module selection");
        assertTrue(nextId == 1, "module id");

        assertEq(
            pufferProtocol.getNextValidatorToBeProvisionedIndex(PUFFER_MODULE_0), 1, "next idx for no restaking module"
        );

        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(_getPubKey(bytes32("alice")), 1, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);
    }

    function test_create_puffer_module() public {
        bytes32 name = bytes32("LEVERAGED_RESTAKING");
        pufferProtocol.createPufferModule(name);
        PufferModule module = PufferModule(payable(pufferProtocol.getModuleAddress(name)));
        assertEq(module.NAME(), name, "name");
    }

    // Test smart contract upgradeability (UUPS)
    function test_upgrade() public {
        vm.expectRevert();
        uint256 result = PufferProtocolMockUpgrade(payable(address(pufferVault))).returnSomething();

        PufferProtocolMockUpgrade newImplementation = new PufferProtocolMockUpgrade(address(beacon));
        pufferProtocol.upgradeToAndCall(address(newImplementation), "");

        result = PufferProtocolMockUpgrade(payable(address(pufferProtocol))).returnSomething();

        assertEq(result, 1337);
    }

    // Test registering the validator with a huge number of months committed
    /// forge-config: default.allow_internal_expect_revert = true
    function test_register_validator_with_huge_commitment() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));

        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        vm.expectRevert();
        pufferProtocol.registerValidatorKey{ value: type(uint256).max }(
            validatorKeyData, PUFFER_MODULE_0, 0, new bytes[](0)
        );
    }

    function test_register_validator_key_new_flow() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));

        vm.deal(alice, 10 ether);

        uint256 amount = BOND + (pufferOracle.getValidatorTicketPrice() * MINIMUM_EPOCHS_VALIDATION);

        vm.startPrank(alice);

        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 0, "zero pufETH before registration");

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0);
        pufferProtocol.registerValidatorKey{ value: amount }(data, PUFFER_MODULE_0, 0, new bytes[](0));

        assertApproxEqAbs(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))), BOND, 1, "1 pufETH after"
        );
        assertEq(address(pufferProtocol).balance, amount - BOND, "amount locked in the protocol");
    }

    function test_register_validator_key_new_flow_with_eth_deposit() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));

        vm.deal(alice, 10 ether);

        uint256 amount = BOND + (pufferOracle.getValidatorTicketPrice() * MINIMUM_EPOCHS_VALIDATION);

        vm.startPrank(alice);

        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 0, "zero pufETH before registration");

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0);
        pufferProtocol.registerValidatorKey{ value: amount }(data, PUFFER_MODULE_0, 0, new bytes[](0));
        vm.stopPrank();

        assertApproxEqAbs(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))), BOND, 1, "1 pufETH after"
        );
        assertEq(address(pufferProtocol).balance, amount - BOND, "amount locked in the protocol");

        // Provision a newly registered validator
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        // 30 Days later, Alice wants to top-up more VT
        vm.warp(block.timestamp + 10 days);

        // reduced by 100000000000 wei
        pufferOracle.setMintPrice(9703921568628);

        // alice validated for 10 days * 225 epochs = 2250 epochs with 1 validator
        // uint256 vtBurnAmount = validatedEpochs * 4444444444444445
        uint256 validatedEpochs = 2250;

        bytes[] memory vtConsumptionSignatures = _getGuardianSignaturesForRegistration(alice, validatedEpochs);

        vm.startPrank(alice);
        pufferProtocol.depositValidationTime{ value: 1 ether }(alice, validatedEpochs, vtConsumptionSignatures);
        vm.stopPrank();
    }

    function testRevert_invalidETHPayment() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));
        vm.deal(alice, 100 ether);

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        // Underpay VT
        vm.expectRevert();
        pufferProtocol.registerValidatorKey{ value: 0.1 ether }(data, PUFFER_MODULE_0, 0, new bytes[](0));
    }

    function test_validator_limit_per_module() external {
        _registerValidatorKey(address(this), bytes32("alice"), PUFFER_MODULE_0, 0);

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorLimitPerModuleChanged(500, 1);
        pufferProtocol.setValidatorLimitPerModule(PUFFER_MODULE_0, 1);

        // Revert if the registration will be over the limit
        uint256 smoothingCommitment = pufferOracle.getValidatorTicketPrice();
        bytes memory pubKey = _getPubKey(bytes32("bob"));
        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        vm.expectRevert(IPufferProtocol.ValidatorLimitForModuleReached.selector);
        pufferProtocol.registerValidatorKey{ value: (smoothingCommitment + BOND) }(
            validatorKeyData, PUFFER_MODULE_0, 0, new bytes[](0)
        );
    }

    function test_claim_bond_for_single_withdrawal() external {
        uint256 startTimestamp = 1707411226;

        // Alice registers one validator and we provision it
        vm.deal(alice, 3 ether);
        vm.deal(NoRestakingModule, 200 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        assertApproxEqAbs(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1.5 ether,
            1,
            "~1.5 pufETH in protocol"
        );

        // bond + something for the validator registration
        assertEq(address(pufferVault).balance, 1001.5 ether, "vault eth balance");

        Validator memory validator = pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 0);

        assertEq(validator.bond, pufferVault.balanceOf(address(pufferProtocol)), "alice bond is in the protocol");

        vm.warp(startTimestamp);

        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        // Didn't claim the bond yet
        assertEq(pufferVault.balanceOf(alice), 0, "alice has zero pufETH");

        // 15 days later (+16 is because 1 day is the start offset)
        vm.warp(startTimestamp + 16 days);

        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            module: NoRestakingModule,
            moduleName: PUFFER_MODULE_0,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            totalEpochsValidated: 16 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 16 * EPOCHS_PER_DAY),
            wasSlashed: false
        });

        // Valid proof
        _executeFullWithdrawal(validatorInfo);

        // Alice got the pufETH
        assertEq(pufferVault.balanceOf(alice), validator.bond, "alice got the pufETH");
        // 1 wei diff
        assertApproxEqAbs(
            pufferVault.convertToAssets(pufferVault.balanceOf(alice)), 1.5 ether, 1, "assets owned by alice"
        );

        // Alice doesn't withdraw her VT's right away
        vm.warp(startTimestamp + 50 days);
    }

    // Alice deposits VT for herself
    function test_deposit_validator_tickets_approval() public {
        vm.deal(alice, 10 ether);

        uint256 numberOfDays = 200;
        uint256 amount = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        vm.startPrank(alice);
        // Alice purchases VT
        validatorTicket.purchaseValidatorTicket{ value: amount }(alice);

        assertEq(validatorTicket.balanceOf(alice), 200 ether, "alice got 200 VT");
        assertEq(validatorTicket.balanceOf(address(pufferProtocol)), 0, "protocol got 0 VT");

        Permit memory vtPermit = emptyPermit;
        vtPermit.amount = 200 ether;

        // Approve VT
        validatorTicket.approve(address(pufferProtocol), 2000 ether);

        // Deposit for herself
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorTicketsDeposited(alice, alice, 200 ether);
        pufferProtocol.depositValidatorTickets(vtPermit, alice);

        assertEq(validatorTicket.balanceOf(address(pufferProtocol)), 200 ether, "protocol got 200 VT");
        assertEq(validatorTicket.balanceOf(address(alice)), 0, "alice got 0");
    }

    // Alice double deposit VT
    function test_double_deposit_validator_tickets_approval() public {
        vm.deal(alice, 1000 ether);

        uint256 numberOfDays = 1000;
        uint256 amount = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        vm.startPrank(alice);
        // Alice purchases VT
        validatorTicket.purchaseValidatorTicket{ value: amount }(alice);

        assertEq(validatorTicket.balanceOf(alice), 1000 ether, "alice got 1000 VT");
        assertEq(validatorTicket.balanceOf(address(pufferProtocol)), 0, "protocol got 0 VT");

        Permit memory vtPermit = emptyPermit;
        vtPermit.amount = 200 ether;

        // Approve VT
        validatorTicket.approve(address(pufferProtocol), 2000 ether);

        // Deposit for herself
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorTicketsDeposited(alice, alice, 200 ether);
        pufferProtocol.depositValidatorTickets(vtPermit, alice);

        assertEq(validatorTicket.balanceOf(address(pufferProtocol)), 200 ether, "protocol got 200 VT");
        assertEq(validatorTicket.balanceOf(address(alice)), 800 ether, "alice got 800");
        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 200 ether, "alice got 200 VT in the protocol");

        // Perform a second deposit of 800 VT
        vtPermit.amount = 800 ether;
        pufferProtocol.depositValidatorTickets((vtPermit), alice);
        assertEq(
            pufferProtocol.getValidatorTicketsBalance(alice), 1000 ether, "alice should have 1000 vt in the protocol"
        );
    }

    // Alice deposits VT for bob
    function test_deposit_validator_tickets_permit_for_bob() public {
        vm.deal(alice, 10 ether);

        uint256 numberOfDays = 200;
        uint256 amount = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        vm.startPrank(alice);
        // Alice purchases VT
        validatorTicket.purchaseValidatorTicket{ value: amount }(alice);

        assertEq(validatorTicket.balanceOf(alice), 200 ether, "alice got 200 VT");
        assertEq(validatorTicket.balanceOf(address(pufferProtocol)), 0, "protocol got 0 VT");

        // Sign the permit
        Permit memory vtPermit = _signPermit(
            _testTemps("alice", address(pufferProtocol), _upscaleTo18Decimals(numberOfDays), block.timestamp),
            validatorTicket.DOMAIN_SEPARATOR()
        );

        // Deposit for Bob
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorTicketsDeposited(bob, alice, 200 ether);
        pufferProtocol.depositValidatorTickets(vtPermit, bob);

        assertEq(pufferProtocol.getValidatorTicketsBalance(bob), 200 ether, "bob got the VTS in the protocol");
        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 0, "alice got no VTS in the protocol");
    }

    // Alice double deposit VT for Bob
    function test_double_deposit_validator_tickets_permit_for_bob() public {
        vm.deal(alice, 1000 ether);

        uint256 numberOfDays = 1000;
        uint256 amount = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        vm.startPrank(alice);
        // Alice purchases VT
        validatorTicket.purchaseValidatorTicket{ value: amount }(alice);

        assertEq(validatorTicket.balanceOf(alice), 1000 ether, "alice got 1000 VT");
        assertEq(validatorTicket.balanceOf(address(pufferProtocol)), 0, "protocol got 0 VT");

        // Sign the permit
        Permit memory vtPermit = _signPermit(
            _testTemps("alice", address(pufferProtocol), _upscaleTo18Decimals(200), block.timestamp),
            validatorTicket.DOMAIN_SEPARATOR()
        );

        // Deposit for Bob
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorTicketsDeposited(bob, alice, 200 ether);
        pufferProtocol.depositValidatorTickets(vtPermit, bob);

        assertEq(pufferProtocol.getValidatorTicketsBalance(bob), 200 ether, "bob got the VTS in the protocol");
        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 0, "alice got no VTS in the protocol");
        assertEq(validatorTicket.balanceOf(alice), 800 ether, "Alice still has 800 VTs left in wallet");

        vm.startPrank(alice);
        // Deposit for Bob again
        Permit memory vtPermit2 = _signPermit(
            _testTemps("alice", address(pufferProtocol), _upscaleTo18Decimals(800), block.timestamp + 1000),
            validatorTicket.DOMAIN_SEPARATOR()
        );
        validatorTicket.approve(address(pufferProtocol), 800 ether);
        pufferProtocol.depositValidatorTickets(vtPermit2, bob);

        assertEq(pufferProtocol.getValidatorTicketsBalance(bob), 1000 ether, "bob got the VTS in the protocol");
        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 0, "alice got no VTS in the protocol");
        assertEq(validatorTicket.balanceOf(alice), 0, "Alice has no more VTs");
    }

    function test_changeMinimumVTAmount() public {
        assertEq(pufferProtocol.getMinimumVtAmount(), 30 * EPOCHS_PER_DAY, "initial value");

        vm.startPrank(DAO);
        pufferProtocol.changeMinimumVTAmount(50 * EPOCHS_PER_DAY);

        assertEq(pufferProtocol.getMinimumVtAmount(), 50 * EPOCHS_PER_DAY, "value after change");
    }

    // Alice tries to withdraw all VT before provisioning
    function test_withdraw_vt_before_provisioning() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);

        // Register Validator key registers validator with 30 VTs
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);

        vm.expectRevert(IPufferProtocol.ActiveOrPendingValidatorsExist.selector);
        pufferProtocol.withdrawValidatorTickets(30 ether, alice);
    }

    function test_register_skip_provision_withdraw_vt() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);

        uint256 vtPrice = pufferOracle.getValidatorTicketPrice();

        assertApproxEqRel(
            pufferProtocol.getValidationTime(alice),
            30 * EPOCHS_PER_DAY * vtPrice,
            pointZeroZeroOne,
            "alice should have ~30 VTS"
        );

        vm.stopPrank();
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.NumberOfRegisteredValidatorsChanged(PUFFER_MODULE_0, 0);
        pufferProtocol.skipProvisioning(PUFFER_MODULE_0, _getGuardianSignaturesForSkipping());

        assertApproxEqRel(
            pufferProtocol.getValidationTime(alice),
            20 * EPOCHS_PER_DAY * vtPrice,
            pointZeroZeroOne,
            "alice should have ~20 VTS -10 penalty"
        );
    }

    function test_setVTPenalty() public {
        // 10 days of VT penalty
        uint256 penaltyETHAmount = 10 * EPOCHS_PER_DAY;
        assertEq(pufferProtocol.getVTPenalty(), penaltyETHAmount, "initial value");

        uint256 newPenaltyAmount = 20 * EPOCHS_PER_DAY;

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.VTPenaltyChanged(penaltyETHAmount, newPenaltyAmount);
        pufferProtocol.setVTPenalty(newPenaltyAmount);

        assertEq(pufferProtocol.getVTPenalty(), newPenaltyAmount, "value after change");
    }

    function test_setVTPenalty_bigger_than_minimum_VT_amount() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferProtocol.InvalidVTAmount.selector);
        pufferProtocol.setVTPenalty(50 * EPOCHS_PER_DAY);
    }

    function test_changeMinimumVTAmount_lower_than_penalty() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferProtocol.InvalidVTAmount.selector);
        pufferProtocol.changeMinimumVTAmount(9 * EPOCHS_PER_DAY);
    }

    function test_new_vtPenalty_works() public {
        // sets VT penalty to 20
        test_setVTPenalty();

        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        uint256 vtPricePerEpoch = pufferOracle.getValidatorTicketPrice();

        assertApproxEqRel(
            pufferProtocol.getValidationTime(alice),
            30 * EPOCHS_PER_DAY * vtPricePerEpoch,
            pointZeroZeroOne,
            "alice should have ~30 VTS"
        );

        pufferProtocol.skipProvisioning(PUFFER_MODULE_0, _getGuardianSignaturesForSkipping());

        // Alice loses 20 VT's
        assertApproxEqRel(
            pufferProtocol.getValidationTime(alice),
            10 * EPOCHS_PER_DAY * vtPricePerEpoch,
            pointZeroZeroOne,
            "alice should have ~10 VTS"
        );

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        // Alice is not provisioned
        assertApproxEqRel(
            pufferProtocol.getValidationTime(alice),
            40 * EPOCHS_PER_DAY * vtPricePerEpoch,
            pointZeroZeroOne,
            "alice should have ~40 VTS"
        );

        // Set penalty to 0
        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.VTPenaltyChanged(20 * EPOCHS_PER_DAY, 0);
        pufferProtocol.setVTPenalty(0);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        assertApproxEqRel(
            pufferProtocol.getValidationTime(alice),
            70 * EPOCHS_PER_DAY * vtPricePerEpoch,
            pointZeroZeroOne,
            "alice should have ~70 VTS register"
        );

        pufferProtocol.skipProvisioning(PUFFER_MODULE_0, _getGuardianSignaturesForSkipping());

        assertApproxEqRel(
            pufferProtocol.getValidationTime(alice),
            70 * EPOCHS_PER_DAY * vtPricePerEpoch,
            pointZeroZeroOne,
            "alice should have ~70 VTS end"
        );
    }

    function test_double_withdrawal_reverts() public {
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);

        assertApproxEqAbs(
            _getUnderlyingETHAmount(address(pufferProtocol)), 1.5 ether, 1, "protocol should have ~2 eth bond"
        );

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("alice")), 0, PUFFER_MODULE_0, 0, 28 * EPOCHS_PER_DAY * BURN_RATE_PER_EPOCH
        );
        _executeFullWithdrawal(
            StoppedValidatorInfo({
                module: NoRestakingModule,
                moduleName: PUFFER_MODULE_0,
                pufferModuleIndex: 0,
                withdrawalAmount: 32 ether,
                totalEpochsValidated: 28 * EPOCHS_PER_DAY,
                vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 28 * EPOCHS_PER_DAY),
                wasSlashed: false
            })
        );

        // 2 days are leftover from 30 (30 is minimum for registration)
        uint256 leftOverTime = 2 * EPOCHS_PER_DAY * pufferOracle.getValidatorTicketPrice();

        uint256 unusedValidationTime = pufferProtocol.getValidationTime(alice);

        assertEq(unusedValidationTime, leftOverTime, "unused validation time");

        // VTS got burned from puffer protocol
        assertEq(address(pufferProtocol).balance, unusedValidationTime, "Protocol has some leftower ETH - unused VT");

        vm.startPrank(alice);
        pufferProtocol.withdrawValidationTime(uint96(unusedValidationTime), address(55));

        assertEq(weth.balanceOf(address(55)), unusedValidationTime, "recipient got the validation time ETH");

        assertApproxEqAbs(_getUnderlyingETHAmount(address(alice)), 1.5 ether, 1, "alice got back the bond");

        bytes[] memory vtConsumptionSignature = _getGuardianSignaturesForRegistration(alice, 28 * EPOCHS_PER_DAY);

        // We've removed the validator data, meaning the validator status is 0 (UNINITIALIZED)
        vm.expectRevert(abi.encodeWithSelector(IPufferProtocol.InvalidValidatorState.selector, 0));
        _executeFullWithdrawal(
            StoppedValidatorInfo({
                module: NoRestakingModule,
                moduleName: PUFFER_MODULE_0,
                pufferModuleIndex: 0,
                withdrawalAmount: 32 ether,
                totalEpochsValidated: 28 * EPOCHS_PER_DAY,
                vtConsumptionSignature: vtConsumptionSignature,
                wasSlashed: false
            })
        );
    }

    // After full withdrawals the node operators claim the remaining VTs
    function test_vt_withdrawals_after_batch_claim() public {
        test_batch_claim();

        assertEq(validatorTicket.balanceOf(alice), 0, "0 vt alice before");

        uint256 aliceVTBalance = pufferProtocol.getValidatorTicketsBalance(alice);

        assertEq(aliceVTBalance, 0, "0 vt token balance after");

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorTicketsWithdrawn(alice, alice, aliceVTBalance);
        pufferProtocol.withdrawValidatorTickets(uint96(aliceVTBalance), alice);

        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 0, "0 vt token balance after");
        assertEq(validatorTicket.balanceOf(alice), aliceVTBalance, "~20 vt alice before");

        uint256 bobVTBalance = pufferProtocol.getValidatorTicketsBalance(bob);

        assertEq(bobVTBalance, 0, "2 vt balance before bob");

        vm.startPrank(bob);

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorTicketsWithdrawn(bob, alice, bobVTBalance);
        pufferProtocol.withdrawValidatorTickets(uint96(bobVTBalance), alice);

        assertEq(pufferProtocol.getValidatorTicketsBalance(bob), 0, "0 vt token balance after bob");
    }

    // Batch claim 32 ETH withdrawals
    function test_batch_claim() public {
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);
        _registerAndProvisionNode(bytes32("bob"), PUFFER_MODULE_0, bob);

        // 28 days of epochs
        uint256 epochsValidated = 28 * EPOCHS_PER_DAY;

        StoppedValidatorInfo memory aliceInfo = StoppedValidatorInfo({
            module: NoRestakingModule,
            moduleName: PUFFER_MODULE_0,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            totalEpochsValidated: epochsValidated,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, epochsValidated),
            wasSlashed: false
        });

        StoppedValidatorInfo memory bobInfo = StoppedValidatorInfo({
            module: NoRestakingModule,
            moduleName: PUFFER_MODULE_0,
            pufferModuleIndex: 1,
            withdrawalAmount: 32 ether,
            totalEpochsValidated: epochsValidated,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, epochsValidated),
            wasSlashed: false
        });

        StoppedValidatorInfo[] memory stopInfos = new StoppedValidatorInfo[](2);
        stopInfos[0] = aliceInfo;
        stopInfos[1] = bobInfo;

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("alice")), 0, PUFFER_MODULE_0, 0, epochsValidated * BURN_RATE_PER_EPOCH
        );
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("bob")), 1, PUFFER_MODULE_0, 0, epochsValidated * BURN_RATE_PER_EPOCH
        );
        pufferProtocol.batchHandleWithdrawals(stopInfos, _getHandleBatchWithdrawalMessage(stopInfos));

        assertEq(_getUnderlyingETHAmount(address(pufferProtocol)), 0 ether, "protocol should have 0 eth bond");

        assertEq(_getUnderlyingETHAmount(address(alice)), 1.5 ether, "alice got back the bond gt");

        assertEq(_getUnderlyingETHAmount(address(bob)), 1.5 ether, "bob got back the bond");
    }

    // Batch claim of different amounts
    // This one uses old validator tickets instead of new VT model
    function test_different_amounts_batch_claim() public {
        // Buy and approve VT
        validatorTicket.purchaseValidatorTicket{ value: 10 ether }(address(this));
        validatorTicket.approve(address(pufferProtocol), 2000 ether);

        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);
        _registerAndProvisionNode(bytes32("bob"), PUFFER_MODULE_0, bob);
        _registerAndProvisionNode(bytes32("charlie"), PUFFER_MODULE_0, charlie);
        _registerAndProvisionNode(bytes32("dianna"), PUFFER_MODULE_0, dianna);
        _registerAndProvisionNode(bytes32("eve"), PUFFER_MODULE_0, eve);

        // Free VTS for everybody!!
        Permit memory vtPermit = emptyPermit;
        vtPermit.amount = 100 ether;
        pufferProtocol.depositValidatorTickets(vtPermit, alice);
        pufferProtocol.depositValidatorTickets(vtPermit, bob);
        pufferProtocol.depositValidatorTickets(vtPermit, charlie);
        pufferProtocol.depositValidatorTickets(vtPermit, dianna);
        pufferProtocol.depositValidatorTickets(vtPermit, eve);

        StoppedValidatorInfo[] memory stopInfos = new StoppedValidatorInfo[](5);
        stopInfos[0] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            totalEpochsValidated: 35 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 35 * EPOCHS_PER_DAY),
            wasSlashed: false
        });
        stopInfos[1] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 1,
            withdrawalAmount: 31.9 ether,
            totalEpochsValidated: 28 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(bob, 28 * EPOCHS_PER_DAY),
            wasSlashed: false
        });
        stopInfos[2] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 2,
            withdrawalAmount: 31 ether,
            totalEpochsValidated: 34 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(charlie, 34 * EPOCHS_PER_DAY),
            wasSlashed: true
        });
        stopInfos[3] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 3,
            withdrawalAmount: 31.8 ether,
            totalEpochsValidated: 48 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(dianna, 48 * EPOCHS_PER_DAY),
            wasSlashed: false
        });
        stopInfos[4] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 4,
            withdrawalAmount: 31.5 ether,
            totalEpochsValidated: 2 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(eve, 2 * EPOCHS_PER_DAY),
            wasSlashed: true
        });

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("alice")), 0, PUFFER_MODULE_0, 0, 35 * EPOCHS_PER_DAY * BURN_RATE_PER_EPOCH
        );
        vm.expectEmit(true, true, true, true);

        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("bob")),
            1,
            PUFFER_MODULE_0,
            pufferVault.convertToSharesUp(0.1 ether),
            28 * EPOCHS_PER_DAY * BURN_RATE_PER_EPOCH
        );
        vm.expectEmit(true, true, true, true);

        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("charlie")),
            2,
            PUFFER_MODULE_0,
            pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 2).bond,
            34 * EPOCHS_PER_DAY * BURN_RATE_PER_EPOCH
        ); // got slashed
        vm.expectEmit(true, true, true, true);

        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("dianna")),
            3,
            PUFFER_MODULE_0,
            pufferVault.convertToSharesUp(0.2 ether),
            48 * EPOCHS_PER_DAY * BURN_RATE_PER_EPOCH
        );
        vm.expectEmit(true, true, true, true);

        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("eve")),
            4,
            PUFFER_MODULE_0,
            pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 4).bond,
            2.00000000000000025 ether // because of rounding we take a little more (28 days of VT)
        ); // got slashed
        pufferProtocol.batchHandleWithdrawals(stopInfos, _getHandleBatchWithdrawalMessage(stopInfos));

        assertEq(_getUnderlyingETHAmount(address(pufferProtocol)), 0 ether, "protocol should have 0 eth bond");

        // // Alice got more because she earned the rewards from the others
        assertGe(_getUnderlyingETHAmount(address(alice)), 1.5 ether, "alice got back the bond gt");

        // // Bob got 0.9 ETH bond + some rewards from the others
        assertGe(_getUnderlyingETHAmount(address(bob)), 0.9 ether, "bob got back the bond gt");

        // // Charlie got 0 bond
        assertEq(_getUnderlyingETHAmount(address(charlie)), 0, "charlie got 0 bond - slashed");

        assertGe(_getUnderlyingETHAmount(address(dianna)), 0.8 ether, "dianna got back the bond gt");

        assertEq(_getUnderlyingETHAmount(address(eve)), 0, "eve got 0 bond - slashed");
    }

    function test_oldVT_and_new_VT_model_only_vt_burned() public {
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "initial exchange rate is 1:1");

        // Buy and approve VT, this changes the exchange rate
        validatorTicket.purchaseValidatorTicket{ value: 1 ether }(address(this));
        validatorTicket.approve(address(pufferProtocol), 1000 ether);

        uint256 exchangeRateAfterVTPurchase = 1000945000000000000;

        // Exchange rate remained unchanged, 1 wei diff (rounding)
        assertApproxEqAbs(
            pufferVault.convertToAssets(1 ether), exchangeRateAfterVTPurchase, 1, "initial exchange rate is ~1:1"
        );

        Permit memory vtPermit = emptyPermit;
        vtPermit.amount = 100 ether;
        pufferProtocol.depositValidatorTickets(vtPermit, alice);

        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 100 ether, "100 VT in the protocol");

        // Alice is provisioned with 30 'new VT' and has 100 validator tickets deposited
        // Total 130 'days' of validation
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);

        uint256 initialValidationTimeAfterProvisioning = pufferProtocol.getValidationTime(alice);

        // Alice exits a validator after 65 days of validation
        StoppedValidatorInfo[] memory stopInfos = new StoppedValidatorInfo[](1);
        stopInfos[0] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            totalEpochsValidated: 65 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 65 * EPOCHS_PER_DAY),
            wasSlashed: false
        });

        // Exchange rate remained unchanged, 1 wei diff (rounding)
        assertApproxEqAbs(pufferVault.convertToAssets(1 ether), exchangeRateAfterVTPurchase, 1, "exchange rate is ~1:1");

        pufferProtocol.batchHandleWithdrawals(stopInfos, _getHandleBatchWithdrawalMessage(stopInfos));

        // Validation time is unchanged
        assertEq(
            pufferProtocol.getValidationTime(alice),
            initialValidationTimeAfterProvisioning,
            "Alice has the same amount of validation time"
        );

        // Alice has 100-65 days of VT left
        assertEq(
            pufferProtocol.getValidatorTicketsBalance(alice),
            34.999999999999991875 ether,
            "Alice has ~35 VT in the protocol"
        );

        // txs don't revert
        vm.startPrank(alice);
        pufferProtocol.withdrawValidationTime(uint96(initialValidationTimeAfterProvisioning), alice);
        pufferProtocol.withdrawValidatorTickets(34.999999999999991875 ether, alice);

        // Alice has 0 VT in the protocol
        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 0, "Alice has 0 VT in the protocol");

        // Alice has 0 validation time
        assertEq(pufferProtocol.getValidationTime(alice), 0, "Alice has 0 validation time");
    }

    function test_oldVT_and_new_VT_model_only_both_burned() public {
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "initial exchange rate is 1:1");

        // Buy and approve VT, this changes the exchange rate
        validatorTicket.purchaseValidatorTicket{ value: 1 ether }(address(this));
        validatorTicket.approve(address(pufferProtocol), 1000 ether);

        uint256 exchangeRateAfterVTPurchase = 1000945000000000000;

        // Exchange rate remained unchanged, 1 wei diff (rounding)
        assertApproxEqAbs(
            pufferVault.convertToAssets(1 ether), exchangeRateAfterVTPurchase, 1, "initial exchange rate is ~1:1"
        );

        Permit memory vtPermit = emptyPermit;
        vtPermit.amount = 100 ether;
        pufferProtocol.depositValidatorTickets(vtPermit, alice);

        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 100 ether, "100 VT in the protocol");

        // Alice is provisioned with 30 'new VT' and has 100 validator tickets deposited
        // Total 130 'days' of validation
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);

        // Alice exits a validator after 120 days of validation
        StoppedValidatorInfo[] memory stopInfos = new StoppedValidatorInfo[](1);
        stopInfos[0] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            totalEpochsValidated: 120 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 120 * EPOCHS_PER_DAY),
            wasSlashed: false
        });

        // Exchange rate remained unchanged, 1 wei diff (rounding)
        assertApproxEqAbs(pufferVault.convertToAssets(1 ether), exchangeRateAfterVTPurchase, 1, "exchange rate is ~1:1");

        pufferProtocol.batchHandleWithdrawals(stopInfos, _getHandleBatchWithdrawalMessage(stopInfos));

        // Nothing is changed, we didn't deposit revenue
        assertApproxEqAbs(pufferVault.convertToAssets(1 ether), exchangeRateAfterVTPurchase, 1, "exchange rate is ~1:1");

        revenueDepositor.depositRevenue();

        assertGt(
            pufferVault.convertToAssets(1 ether),
            exchangeRateAfterVTPurchase,
            "exchange rate is now bigger because of revenue deposit"
        );

        // Alice has 0 VT in the protocol
        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 0, "Alice has 0 VT in the protocol");

        // It is expected to have 10 days of validation time
        uint256 expectedLeftOverValidationTime = 10 * EPOCHS_PER_DAY * pufferOracle.getValidatorTicketPrice();

        // Alice has >0 validation time
        assertEq(
            pufferProtocol.getValidationTime(alice), expectedLeftOverValidationTime, "Alice has >0 validation time"
        );

        vm.startPrank(alice);
        pufferProtocol.withdrawValidationTime(uint96(expectedLeftOverValidationTime), address(8888));

        assertEq(
            weth.balanceOf(address(8888)),
            expectedLeftOverValidationTime,
            "Recipient got WETH (validation time from Alice)"
        );
    }

    function test_single_withdrawal() public {
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);
        _registerAndProvisionNode(bytes32("bob"), PUFFER_MODULE_0, bob);

        StoppedValidatorInfo memory aliceInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            totalEpochsValidated: 28 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 28 * EPOCHS_PER_DAY),
            wasSlashed: false
        });

        StoppedValidatorInfo memory bobInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 1,
            withdrawalAmount: 32 ether,
            totalEpochsValidated: 28 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 28 * EPOCHS_PER_DAY),
            wasSlashed: false
        });

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("alice")), 0, PUFFER_MODULE_0, 0, 28 * EPOCHS_PER_DAY * BURN_RATE_PER_EPOCH
        ); // 10 days of VT
        _executeFullWithdrawal(aliceInfo);
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("bob")), 1, PUFFER_MODULE_0, 0, 28 * EPOCHS_PER_DAY * BURN_RATE_PER_EPOCH
        ); // 10 days of VT
        _executeFullWithdrawal(bobInfo);

        assertApproxEqAbs(
            _getUnderlyingETHAmount(address(pufferProtocol)), 0 ether, 1, "protocol should have 0 eth bond"
        );

        // Alice got more because she earned the rewards from Bob's registration
        assertGe(_getUnderlyingETHAmount(address(alice)), 1.5 ether, "alice got back the bond gt");

        assertApproxEqAbs(_getUnderlyingETHAmount(address(bob)), 1.5 ether, 1, "bob got back the bond");
    }

    function test_batch_vs_multiple_single_withdrawals() public {
        // Trigger the previous test
        test_batch_claim();

        uint256 aliceBalanceBefore = pufferVault.balanceOf(alice);
        uint256 bobBalanceBefore = pufferVault.balanceOf(bob);

        vm.stopPrank();

        // Redeploy the contracts to reset everything
        setUp();

        // Trigger separate withdrawal
        test_single_withdrawal();

        // Assert that the result is the same
        assertEq(aliceBalanceBefore, pufferVault.balanceOf(alice), "alice balance");
        assertEq(bobBalanceBefore, pufferVault.balanceOf(bob), "bob balance");
    }

    function _executeFullWithdrawal(StoppedValidatorInfo memory validatorInfo) internal {
        StoppedValidatorInfo[] memory stopInfos = new StoppedValidatorInfo[](1);
        stopInfos[0] = validatorInfo;

        vm.stopPrank(); // this contract has the PAYMASTER role, so we need to stop the prank
        pufferProtocol.batchHandleWithdrawals({
            validatorInfos: stopInfos,
            guardianEOASignatures: _getHandleBatchWithdrawalMessage(stopInfos)
        });
    }

    // Register 2 validators and provision 1 validator and post full withdrawal proof for 29 eth (slash 3 ETH on one validator)
    // Case 1
    function test_slashing_case_1() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToShares(1 ether);
        // This is because VT settlement now happens later, so the exchange rate is 1:1
        assertEq(exchangeRateBefore, 1 ether, "shares before provisioning, 1:1");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        // Give funds to modules
        vm.deal(NoRestakingModule, 200 ether);

        // Now the node operators submit proofs to get back their bond
        vm.startPrank(alice);
        // Invalid block number = invalid proof
        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            withdrawalAmount: 29 ether,
            totalEpochsValidated: 28 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 28 * EPOCHS_PER_DAY),
            wasSlashed: true
        });

        // Burns two bonds from Alice (she registered 2 validators, but only one got activated)
        // If the other one was active it would get ejected by the guardians
        _executeFullWithdrawal(validatorInfo);

        // 1 ETH gives you more pufETH after the `retrieveBond` call, meaning it is worse than before
        assertLt(exchangeRateBefore, pufferVault.convertToShares(1 ether), "shares after retrieve");

        // The other validator has less than 1 ETH in the bond
        // Bad dept is shared between all pufETH holders
        assertApproxEqRel(
            pufferVault.balanceOf(address(pufferProtocol)),
            1.5 ether,
            pointZeroOne,
            "1.5 ETH worth of pufETH in the protocol"
        );
        assertEq(pufferVault.balanceOf(alice), 0, "0 pufETH alice");
    }

    // Register 2 validators, provision 1, slash 2.5 whole validator bond owned by node operator
    // Case 2
    function test_slashing_case_2() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToShares(1 ether);
        assertEq(exchangeRateBefore, 1 ether, "shares before provisioning, 1:1");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        vm.deal(NoRestakingModule, 200 ether);

        // Now the node operators submit proofs to get back their bond
        vm.startPrank(alice);
        // Invalid block number = invalid proof
        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            totalEpochsValidated: 28 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 28 * EPOCHS_PER_DAY),
            withdrawalAmount: 29.5 ether,
            wasSlashed: true
        });

        // Burns one whole bond
        _executeFullWithdrawal(validatorInfo);

        // 1 ETH gives you more pufETH after the `retrieveBond` call, meaning it is better for pufETH holders
        assertLt(exchangeRateBefore, pufferVault.convertToShares(1 ether), "shares after retrieve");

        // The other validator has less than 1 ETH in the bond
        // Bad dept is shared between all pufETH holders
        assertApproxEqRel(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1.5 ether,
            pointZeroOne,
            "1.5 ether ETH worth of pufETH in the protocol"
        );
        assertEq(pufferVault.balanceOf(alice), 0, "0 pufETH alice");
    }

    // Register 2 validators, provision 1, slash 1 whole validator bond (2 ETH)
    // Case 3
    function test_slashing_case_3() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToAssets(1 ether);
        // 2 bonds * 1.5 ETH + 1000 initial value in the vault
        assertEq(address(pufferVault).balance, 1003 ether, "1003 ETH in the vault");
        assertEq(exchangeRateBefore, 1 ether, "shares before provisioning, 1:1");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        // We provision one validator
        assertEq(address(pufferVault).balance, 971 ether, "971 ETH in the vault");

        // Stays the same
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "shares after provisioning");
        assertEq(weth.balanceOf(address(pufferVault)), 0 ether, "0 WETH in the vault");

        vm.deal(NoRestakingModule, 200 ether);

        // Now the node operators submit proofs to get back their bond
        vm.startPrank(alice);
        // Invalid block number = invalid proof
        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            totalEpochsValidated: 28 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 28 * EPOCHS_PER_DAY),
            withdrawalAmount: 30.9 ether, // 1.1 ETH slashed
            wasSlashed: true
        });

        // Burns one whole bond
        _executeFullWithdrawal(validatorInfo);

        // 30 ETH was returned to the vault
        assertEq(address(pufferVault).balance, 1001.9 ether, "1001.9 ETH in the vault");

        revenueDepositor.depositRevenue();

        assertGt(weth.balanceOf(address(pufferVault)), 0 ether, "WETH in the vault");

        // Exchange rate changes in favour of remaining pufETH holders
        assertLt(
            exchangeRateBefore,
            pufferVault.convertToAssets(1 ether),
            "exchange rate after validator exits is better for pufETH holders"
        );

        // Alice has a little over 1.5 ETH because she earned something from herself (her own exit + slashing)
        assertApproxEqRel(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1.5 ether,
            pointZeroOne,
            "1.5 ETH worth of pufETH in the protocol"
        );
        // Alice didn't receive any bond for that one validator exit
        assertEq(pufferVault.balanceOf(alice), 0, "0 pufETH alice");
    }

    // Register 2 validators, provision 1, no slashing, but validator was offline and lost 0.1 ETH
    // Case 4
    function test_slashing_case_4() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToShares(1 ether);
        assertEq(exchangeRateBefore, 1 ether, "shares before provisioning");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        vm.deal(NoRestakingModule, 200 ether);

        // Now the node operators submit proofs to get back their bond
        vm.startPrank(alice);
        // Invalid block number = invalid proof
        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            totalEpochsValidated: 28 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 28 * EPOCHS_PER_DAY),
            withdrawalAmount: 31.9 ether,
            wasSlashed: false
        });

        // Burns one whole bond
        _executeFullWithdrawal(validatorInfo);

        revenueDepositor.depositRevenue();

        // Exchange rate is better for pufETH holders
        assertGt(exchangeRateBefore, pufferVault.convertToShares(1 ether), "shares after retrieve");

        // Alice has ~ 1.5 ETH locked in the protocol
        assertApproxEqRel(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1.5 ether,
            pointZeroOne,
            "1.5 ETH worth of pufETH in the protocol"
        );
        // Alice got a little over 0.9 ETH worth of pufETH because she earned something for paying the VT on the second validator registration
        assertGt(pufferVault.convertToAssets(pufferVault.balanceOf(alice)), 0.9 ether, ">0.9 ETH worth of pufETH alice");
    }

    // Register 2 validators, provision 1, no slashing, validator exited with 32.1 ETH
    // Case 5
    function test_slashing_case_5() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToShares(1 ether);
        assertEq(exchangeRateBefore, 1 ether, "shares before provisioning");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        vm.deal(NoRestakingModule, 200 ether);

        // Now the node operators submit proofs to get back their bond
        vm.startPrank(alice);
        // Invalid block number = invalid proof
        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            totalEpochsValidated: 15 * EPOCHS_PER_DAY,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 15 * EPOCHS_PER_DAY),
            withdrawalAmount: 32.1 ether,
            wasSlashed: false
        });

        // Burns one whole bond
        _executeFullWithdrawal(validatorInfo);

        revenueDepositor.depositRevenue();

        // Exchange rate is better for pufETH holders
        assertGt(exchangeRateBefore, pufferVault.convertToShares(1 ether), "shares after retrieve");

        // Alice has ~ 1 ETH locked in the protocol
        assertApproxEqRel(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1.5 ether,
            pointZeroZeroOne,
            "1.5 ETH worth of pufETH in the protocol"
        );
        // Alice got a little over 1.5 ETH worth of pufETH because she earned something for paying the VT on the second validator registration
        assertGt(pufferVault.convertToAssets(pufferVault.balanceOf(alice)), 1.5 ether, ">1.5 ETH worth of pufETH alice");
    }

    function test_validator_early_exit_dos() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        // Alice exited after 1 day
        _executeFullWithdrawal(
            StoppedValidatorInfo({
                module: NoRestakingModule,
                moduleName: PUFFER_MODULE_0,
                pufferModuleIndex: 0,
                withdrawalAmount: 32 ether,
                totalEpochsValidated: 1 * EPOCHS_PER_DAY,
                vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 1 * EPOCHS_PER_DAY),
                wasSlashed: false
            })
        );

        uint256 leftOverValidationTime = 20 * EPOCHS_PER_DAY * pufferOracle.getValidatorTicketPrice();

        assertEq(
            pufferProtocol.getValidationTime(alice), leftOverValidationTime, "alice got 20 days left in the protocol"
        );
    }

    // Alice registers one 30 VT validator
    // DAO changes the minimum VT amount to 35
    // Alice the validator after 3 days
    function test_validator_early_exit_edge_case() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(alice, bytes32("alice"), PUFFER_MODULE_0, 0);
        vm.stopPrank();

        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        vm.startPrank(DAO);
        pufferProtocol.changeMinimumVTAmount(35 ether);
        vm.stopPrank();

        // Alice exited after 1 day
        _executeFullWithdrawal(
            StoppedValidatorInfo({
                module: NoRestakingModule,
                moduleName: PUFFER_MODULE_0,
                pufferModuleIndex: 0,
                withdrawalAmount: 32 ether,
                totalEpochsValidated: 3 * EPOCHS_PER_DAY,
                vtConsumptionSignature: _getGuardianSignaturesForRegistration(alice, 3 * EPOCHS_PER_DAY),
                wasSlashed: false
            })
        );

        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 0 ether, "alice got 0 VT left in the protocol");
    }

    // User deposits a lot of ETH (validator tickets)
    function test_big_eth_deposit() public {
        bytes memory pubKey = _getPubKey(bytes32("alice"));

        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 0, "zero pufETH before");

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        // Register validator key by paying SC in ETH and depositing bond in pufETH
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidationTimeDeposited({ node: address(this), ethAmount: 7.5 ether });
        emit IPufferProtocol.ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0);
        pufferProtocol.registerValidatorKey{ value: 9 ether }(data, PUFFER_MODULE_0, 0, new bytes[](0));

        // Protocol holds 7.5 ETHER
        assertEq(address(pufferProtocol).balance, 7.5 ether, "7.5 ETH in the protocol");
        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 1.5 ether, "Bond in pufETH is held by the protocol");
    }

    // Alice deposits VT to Bob and Bob has no validators in Puffer
    function test_deposit_vt_to_bob() public {
        vm.deal(alice, 10 ether);
        vm.startPrank(alice);
        validatorTicket.purchaseValidatorTicket{ value: 10 ether }(alice);

        Permit memory vtPermit = _signPermit(
            _testTemps("alice", address(pufferProtocol), 50 ether, block.timestamp), validatorTicket.DOMAIN_SEPARATOR()
        );

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorTicketsDeposited(bob, alice, 50 ether);
        pufferProtocol.depositValidatorTickets(vtPermit, bob);

        vm.startPrank(bob);
        pufferProtocol.withdrawValidatorTickets(50 ether, bob);

        assertEq(validatorTicket.balanceOf(bob), 50 ether, "bob got the VT");
    }

    function _getGuardianSignaturesForSkipping() internal view returns (bytes[] memory) {
        (bytes32 moduleName, uint256 pendingIdx) = pufferProtocol.getNextValidatorToProvision();

        bytes32 digest = LibGuardianMessages._getSkipProvisioningMessage(moduleName, pendingIdx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guardian1SK, digest);
        bytes memory signature1 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian2SK, digest);
        bytes memory signature2 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian3SK, digest);
        bytes memory signature3 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        bytes[] memory guardianSignatures = new bytes[](3);
        guardianSignatures[0] = signature1;
        guardianSignatures[1] = signature2;
        guardianSignatures[2] = signature3;

        return guardianSignatures;
    }

    /**
     * @notice Get the guardian signatures from the backend API for the total validated epochs by the node operator
     * @param node The address of the node operator
     * @param validatedEpochsTotal The total number of validated epochs (sum for all the validators and their consumption)
     * @return guardianSignatures The guardian signatures
     */
    function _getGuardianSignaturesForRegistration(address node, uint256 validatedEpochsTotal)
        internal
        view
        returns (bytes[] memory)
    {
        uint256 nonce = pufferProtocol.nonces(node);

        bytes32 digest = keccak256(abi.encode(node, validatedEpochsTotal, nonce));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guardian1SK, digest);
        bytes memory signature1 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian2SK, digest);
        bytes memory signature2 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian3SK, digest);
        bytes memory signature3 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        bytes[] memory guardianSignatures = new bytes[](3);
        guardianSignatures[0] = signature1;
        guardianSignatures[1] = signature2;
        guardianSignatures[2] = signature3;

        return guardianSignatures;
    }

    function _getHandleBatchWithdrawalMessage(StoppedValidatorInfo[] memory validatorInfos)
        internal
        view
        returns (bytes[] memory)
    {
        bytes32 digest = LibGuardianMessages._getHandleBatchWithdrawalMessage(validatorInfos);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guardian1SK, digest);
        bytes memory signature1 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian2SK, digest);
        bytes memory signature2 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian3SK, digest);
        bytes memory signature3 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        bytes[] memory guardianSignatures = new bytes[](3);
        guardianSignatures[0] = signature1;
        guardianSignatures[1] = signature2;
        guardianSignatures[2] = signature3;

        return guardianSignatures;
    }

    // Tests setter for enclave measurements

    function _validatorSignature() internal pure returns (bytes memory validatorSignature) {
        // mock signature copied from some random deposit transaction
        validatorSignature =
            hex"8aa088146c8c6ca6d8ad96648f20e791be7c449ce7035a6bd0a136b8c7b7867f730428af8d4a2b69658bfdade185d6110b938d7a59e98d905e922d53432e216dc88c3384157d74200d3f2de51d31737ce19098ff4d4f54f77f0175e23ac98da5";
    }

    // Generates a mock validator data for 2 ETH case
    function _getMockValidatorKeyData(bytes memory pubKey, bytes32 moduleName)
        internal
        view
        returns (ValidatorKeyData memory)
    {
        bytes[] memory newSetOfPubKeys = new bytes[](3);

        // we have 3 guardians in TestHelper.sol
        newSetOfPubKeys[0] = bytes("key1");
        newSetOfPubKeys[0] = bytes("key2");
        newSetOfPubKeys[0] = bytes("key3");

        address module = pufferProtocol.getModuleAddress(moduleName);

        bytes memory withdrawalCredentials = pufferProtocol.getWithdrawalCredentials(module);

        bytes memory validatorSignature = _validatorSignature();

        ValidatorKeyData memory validatorData = ValidatorKeyData({
            blsPubKey: pubKey, // key length must be 48 byte
            signature: validatorSignature,
            depositDataRoot: pufferProtocol.getDepositDataRoot({
                pubKey: pubKey,
                signature: validatorSignature,
                withdrawalCredentials: withdrawalCredentials
            }),
            deprecated_blsEncryptedPrivKeyShares: new bytes[](3),
            deprecated_blsPubKeySet: new bytes(48),
            deprecated_raveEvidence: new bytes(0)
        });

        return validatorData;
    }

    function _getPubKey(bytes32 pubKeyPart) internal pure returns (bytes memory) {
        return bytes.concat(abi.encodePacked(pubKeyPart), bytes16(""));
    }

    function _createModules() internal {
        // Create EIGEN_DA module
        pufferProtocol.createPufferModule(EIGEN_DA);
        pufferProtocol.setValidatorLimitPerModule(EIGEN_DA, 15);

        // Include the EIGEN_DA in module selection
        bytes32[] memory newWeights = new bytes32[](4);
        newWeights[0] = PUFFER_MODULE_0;
        newWeights[1] = EIGEN_DA;
        newWeights[2] = EIGEN_DA;
        newWeights[3] = CRAZY_GAINS;

        pufferProtocol.setModuleWeights(newWeights);

        eigenDaModule = pufferProtocol.getModuleAddress(EIGEN_DA);
    }

    /**
     * @dev Registers validator key and pays for everything in ETH
     * @dev epochValidated = sum for all all the validators and their consumption
     */
    function _registerValidatorKey(
        address nodeOperator,
        bytes32 pubKeyPart,
        bytes32 moduleName,
        uint256 epochsValidated
    ) internal {
        uint256 amount = BOND + (pufferOracle.getValidatorTicketPrice() * MINIMUM_EPOCHS_VALIDATION);

        bytes memory pubKey = _getPubKey(pubKeyPart);
        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, moduleName);
        uint256 idx = pufferProtocol.getPendingValidatorIndex(moduleName);

        bytes[] memory vtConsumptionSignatures = _getGuardianSignaturesForRegistration(nodeOperator, epochsValidated);

        // Empty permit means that the node operator is paying with ETH for both bond & VT in the registration transaction
        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, idx, moduleName);
        pufferProtocol.registerValidatorKey{ value: amount }(
            validatorKeyData, moduleName, epochsValidated, vtConsumptionSignatures
        );
    }

    /**
     * @dev Registers and provisions a new validator with 2 ETH bond and 30 VTs (see _registerValidatorKey)
     */
    function _registerAndProvisionNode(bytes32 pubKeyPart, bytes32 moduleName, address nodeOperator) internal {
        vm.deal(nodeOperator, 10 ether);

        vm.startPrank(nodeOperator);
        _registerValidatorKey(nodeOperator, pubKeyPart, moduleName, 0);
        vm.stopPrank();

        pufferProtocol.provisionNode(_validatorSignature(), DEFAULT_DEPOSIT_ROOT);
    }

    /**
     * @dev Returns the assets value of the pufETH for a given `target`
     * convertToAssets and previewWithdraw give different results because of the withdrawal fee on the PufferVault
     */
    function _getUnderlyingETHAmount(address target) internal view returns (uint256 ethAmount) {
        return pufferVault.convertToAssets(pufferVault.balanceOf(target));
    }

    function _upscaleTo18Decimals(uint256 amount) internal pure returns (uint256) {
        return amount * 1 ether;
    }

    function _getVTBurnAmount(uint256 startEpoch, uint256 endEpoch) internal pure returns (uint256) {
        uint256 validatedEpochs = endEpoch - startEpoch;
        // Epoch has 32 blocks, each block is 12 seconds, we upscale to 18 decimals to get the VT amount and divide by 1 day
        // The formula is validatedEpochs * 32 * 12 * 1 ether / 1 days (4444444444444444.44444444...) we round it up
        return validatedEpochs * 4444444444444445;
    }

    function test_getNodeInfo() public {
        // Test non-existent node
        NodeInfo memory nodeInfo = pufferProtocol.getNodeInfo(address(0x123));
        assertEq(nodeInfo.activeValidatorCount, 0);
        assertEq(nodeInfo.pendingValidatorCount, 0);
        assertEq(nodeInfo.deprecated_vtBalance, 0);
        assertEq(nodeInfo.validationTime, 0);
        assertEq(nodeInfo.epochPrice, 0);
        assertEq(nodeInfo.totalEpochsValidated, 0);

        // Test registered node (alice)
        nodeInfo = pufferProtocol.getNodeInfo(alice);
        assertEq(nodeInfo.activeValidatorCount, 0);
        assertEq(nodeInfo.pendingValidatorCount, 0);
        assertEq(nodeInfo.deprecated_vtBalance, 0);
        assertEq(nodeInfo.validationTime, 0);
        assertEq(nodeInfo.epochPrice, 0);
        assertEq(nodeInfo.totalEpochsValidated, 0);
    }

    function test_setVTPenalty_invalid_amount() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferProtocol.InvalidVTAmount.selector);
        pufferProtocol.setVTPenalty(type(uint256).max);
    }

    function test_checkValidatorRegistrationInputs_invalid_pubkey() public {
        bytes memory invalidPubKey = new bytes(47); // Invalid length
        ValidatorKeyData memory data = _getMockValidatorKeyData(invalidPubKey, PUFFER_MODULE_0);

        vm.expectRevert(IPufferProtocol.InvalidBLSPubKey.selector);
        pufferProtocol.registerValidatorKey{ value: 3 ether }(data, PUFFER_MODULE_0, 0, new bytes[](0));
    }

    function test_changeMinimumVTAmount_invalid_amount() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferProtocol.InvalidVTAmount.selector);
        pufferProtocol.changeMinimumVTAmount(0);
    }

    function test_panic_batch_withdrawals() public {
        // Test with zero epochs
        StoppedValidatorInfo memory info = StoppedValidatorInfo({
            module: NoRestakingModule,
            moduleName: PUFFER_MODULE_0,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            totalEpochsValidated: type(uint256).max,
            vtConsumptionSignature: _getGuardianSignaturesForRegistration(bob, type(uint256).max),
            wasSlashed: false
        });

        StoppedValidatorInfo[] memory validatorInfos = new StoppedValidatorInfo[](1);
        validatorInfos[0] = info;

        _registerAndProvisionNode(bytes32("bob"), PUFFER_MODULE_0, bob);

        // Panic Error is expected panic: arithmetic underflow or overflow (0x11)
        vm.expectRevert(bytes("panic: arithmetic underflow or overflow (0x11)"));
        pufferProtocol.batchHandleWithdrawals(validatorInfos, _getHandleBatchWithdrawalMessage(validatorInfos));
    }

    function test_useVTOrValidationTime_edge_cases() public {
        // Test with zero VT and validation time
        _registerValidatorKey(address(this), bytes32("alice"), PUFFER_MODULE_0, 0);

        // Test with maximum VT and validation time
        vm.deal(alice, 1000 ether);
        vm.startPrank(alice);
        validatorTicket.purchaseValidatorTicket{ value: 1000 ether }(alice);
        validatorTicket.approve(address(pufferProtocol), type(uint256).max);
        pufferProtocol.depositValidatorTickets(emptyPermit, alice);
        vm.stopPrank();
    }

    function test_settleVTAccounting_edge_cases() public {
        // Test with zero VT balance
        _registerValidatorKey(address(this), bytes32("alice"), PUFFER_MODULE_0, 0);

        // Test with maximum VT balance
        vm.deal(alice, 1000 ether);
        vm.startPrank(alice);
        validatorTicket.purchaseValidatorTicket{ value: 1000 ether }(alice);
        validatorTicket.approve(address(pufferProtocol), type(uint256).max);
        pufferProtocol.depositValidatorTickets(emptyPermit, alice);
        vm.stopPrank();
    }
}

struct MerkleProofData {
    bytes32 moduleName;
    uint256 index;
    uint256 amount;
    uint8 wasSlashed;
}
