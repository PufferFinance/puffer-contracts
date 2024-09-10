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
import { IPufferModule } from "../../src/interface/IPufferModule.sol";
import { ROLE_ID_DAO, ROLE_ID_OPERATIONS_PAYMASTER, ROLE_ID_OPERATIONS_MULTISIG } from "../../script/Roles.sol";
import { Unauthorized } from "../../src/Errors.sol";
import { LibGuardianMessages } from "../../src/LibGuardianMessages.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { ModuleLimit } from "../../src/struct/ProtocolStorage.sol";
import { StoppedValidatorInfo } from "../../src/struct/StoppedValidatorInfo.sol";

contract PufferProtocolTest is UnitTestHelper {
    using ECDSA for bytes32;

    event ValidatorKeyRegistered(bytes pubKey, uint256 indexed, bytes32 indexed, bool);
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
        vm.stopPrank();

        // Set daily withdrawals limit
        pufferVault.setDailyWithdrawalLimit(1000 ether);

        _skipDefaultFuzzAddresses();

        fuzzedAddressMapping[address(pufferProtocol)] = true;

        NoRestakingModule = pufferProtocol.getModuleAddress(PUFFER_MODULE_0);
        // Fund no restaking module with 200 ETH
        vm.deal(NoRestakingModule, 200 ether);
    }

    // Setup
    function test_setup() public view {
        assertTrue(address(pufferProtocol.PUFFER_VAULT()) != address(0), "puffer vault address");
        address module = pufferProtocol.getModuleAddress(PUFFER_MODULE_0);
        assertEq(PufferModule(payable(module)).NAME(), PUFFER_MODULE_0, "bad name");
    }

    // Register validator key
    function test_register_validator_key() public {
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
    }

    // Empty queue should return NO_VALIDATORS
    function test_empty_queue() public view {
        (bytes32 moduleName, uint256 idx) = pufferProtocol.getNextValidatorToProvision();
        assertEq(moduleName, bytes32("NO_VALIDATORS"), "name");
        assertEq(idx, type(uint256).max, "name");
    }

    // Test Skipping the validator
    function test_skip_provisioning() public {
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("bob"), PUFFER_MODULE_0);

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

        bytes[] memory signatures = _getGuardianSignatures(_getPubKey(bytes32("bob")));

        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(_getPubKey(bytes32("bob")), 1, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);
        moduleSelectionIndex = pufferProtocol.getModuleSelectIndex();
        assertEq(moduleSelectionIndex, 1, "module idx changed");
    }

    // Create an existing module should revert
    function test_create_existing_module_fails() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferProtocol.ModuleAlreadyExists.selector);
        pufferProtocol.createPufferModule(PUFFER_MODULE_0);
    }

    // Invalid pub key shares length
    function test_register_invalid_pubkey_shares_length() public {
        ValidatorKeyData memory data = _getMockValidatorKeyData(new bytes(48), PUFFER_MODULE_0);
        data.blsPubKeySet = new bytes(22); // Invalid length

        vm.expectRevert(IPufferProtocol.InvalidBLSPublicKeySet.selector);
        pufferProtocol.registerValidatorKey{ value: 4 ether }(data, PUFFER_MODULE_0, emptyPermit, emptyPermit);
    }

    // Invalid private key shares length
    function test_register_invalid_privKey_shares() public {
        ValidatorKeyData memory data = _getMockValidatorKeyData(new bytes(48), PUFFER_MODULE_0);
        data.blsEncryptedPrivKeyShares = new bytes[](2); // we have 3 guardians, and we try to give 2 priv key shares

        vm.expectRevert(IPufferProtocol.InvalidBLSPrivateKeyShares.selector);
        pufferProtocol.registerValidatorKey{ value: 4 ether }(data, PUFFER_MODULE_0, emptyPermit, emptyPermit);
    }

    // Try registering with invalid module
    function test_register_to_invalid_module() public {
        uint256 smoothingCommitment = pufferOracle.getValidatorTicketPrice() * 30;
        bytes memory pubKey = _getPubKey(bytes32("charlie"));
        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);
        vm.expectRevert(IPufferProtocol.ValidatorLimitForModuleReached.selector);
        pufferProtocol.registerValidatorKey{ value: smoothingCommitment }(
            validatorKeyData, bytes32("imaginary module"), emptyPermit, emptyPermit
        );
    }

    // Mint non whole vt after registration
    function test_register_with_non_whole_amount() public {
        bytes memory pubKey = _getPubKey(bytes32("charlie"));
        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);
        uint256 vtPrice = pufferOracle.getValidatorTicketPrice();
        uint256 amount = 5.11 ether;

        pufferProtocol.registerValidatorKey{ value: amount }(
            validatorKeyData, PUFFER_MODULE_0, emptyPermit, emptyPermit
        );

        assertEq(
            validatorTicket.balanceOf(address(pufferProtocol)),
            ((amount - 1 ether) * 1 ether) / vtPrice,
            "VT after for pufferProtocol"
        );
    }

    // If we are > burst threshold, treasury gets everything
    function test_burst_threshold() external {
        vm.roll(50401);

        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);

        pufferOracle.setTotalNumberOfValidators(
            5,
            99999999,
            _getGuardianEOASignatures(
                LibGuardianMessages._getSetNumberOfValidatorsMessage({ numberOfValidators: 5, epochNumber: 99999999 })
            )
        );

        uint256 sc = pufferOracle.getValidatorTicketPrice() * 30;
        address treasury = validatorTicket.TREASURY();

        uint256 balanceBefore = address(treasury).balance;

        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);

        uint256 balanceAfter = address(treasury).balance;

        assertEq(balanceAfter, balanceBefore + sc, "treasury gets everything");
    }

    // Set validator limit and try registering that many validators
    function test_fuzz_register_many_validators(uint8 numberOfValidatorsToProvision) external {
        for (uint256 i = 0; i < uint256(numberOfValidatorsToProvision); ++i) {
            vm.deal(address(this), 2 ether);
            _registerValidatorKey(bytes32(i), PUFFER_MODULE_0);
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
            blsEncryptedPrivKeyShares: new bytes[](3),
            blsPubKeySet: new bytes(48),
            raveEvidence: new bytes(0) // No rave
         });

        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0, false);
        pufferProtocol.registerValidatorKey{ value: vtPrice + 2 ether }(
            validatorData, PUFFER_MODULE_0, emptyPermit, emptyPermit
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
            blsEncryptedPrivKeyShares: new bytes[](3),
            blsPubKeySet: new bytes(144),
            raveEvidence: new bytes(1)
        });

        vm.expectRevert(IPufferProtocol.InvalidBLSPubKey.selector);
        pufferProtocol.registerValidatorKey{ value: smoothingCommitment }(
            validatorData, PUFFER_MODULE_0, emptyPermit, emptyPermit
        );
    }

    function test_get_payload() public view {
        (bytes[] memory guardianPubKeys,, uint256 threshold,) = pufferProtocol.getPayload(PUFFER_MODULE_0, false);

        assertEq(guardianPubKeys[0], guardian1EnclavePubKey, "guardian1");
        assertEq(guardianPubKeys[1], guardian2EnclavePubKey, "guardian2");
        assertEq(guardianPubKeys[2], guardian3EnclavePubKey, "guardian3");

        assertEq(guardianPubKeys.length, 3, "pubkeys len");
        assertEq(threshold, 1, "threshold");
    }

    // Try to provision a validator when there is nothing to provision
    function test_provision_reverts() public {
        (, uint256 idx) = pufferProtocol.getNextValidatorToProvision();
        assertEq(type(uint256).max, idx, "module");

        // Invalid signatures
        bytes[] memory signatures =
            _getGuardianSignatures(hex"0000000000000000000000000000000000000000000000000000000000000000");

        vm.expectRevert(); // panic
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);
    }

    // If the deposit root is not bytes(0), it must match match the one returned from the beacon contract
    function test_provision_bad_deposit_hash() public {
        _registerValidatorKey(zeroPubKeyPart, PUFFER_MODULE_0);

        bytes memory validatorSignature = _validatorSignature();
        bytes[] memory guardianSignatures = _getGuardianSignatures(_getPubKey(zeroPubKeyPart));

        vm.expectRevert(IPufferProtocol.InvalidDepositRootHash.selector);
        pufferProtocol.provisionNode(guardianSignatures, validatorSignature, bytes32("badDepositRoot")); // "depositRoot" is hardcoded in the mock

        // now it works
        pufferProtocol.provisionNode(guardianSignatures, validatorSignature, DEFAULT_DEPOSIT_ROOT);
    }

    function test_register_multiple_validators_and_skipProvisioning(bytes32 alicePubKeyPart, bytes32 bobPubKeyPart)
        public
    {
        vm.deal(bob, 10 ether);

        vm.deal(alice, 10 ether);

        bytes memory bobPubKey = _getPubKey(bobPubKeyPart);

        // 1. validator
        _registerValidatorKey(zeroPubKeyPart, PUFFER_MODULE_0);

        Validator memory validator = pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 0);
        assertTrue(validator.node == address(this), "node operator");
        assertTrue(keccak256(validator.pubKey) == keccak256(zeroPubKey), "bad pubkey");

        // 2. validator
        vm.startPrank(bob);
        _registerValidatorKey(bobPubKeyPart, PUFFER_MODULE_0);
        vm.stopPrank();

        // 3. validator
        vm.startPrank(alice);
        _registerValidatorKey(alicePubKeyPart, PUFFER_MODULE_0);
        vm.stopPrank();

        // 4. validator
        _registerValidatorKey(zeroPubKeyPart, PUFFER_MODULE_0);

        // 5. Validator
        _registerValidatorKey(zeroPubKeyPart, PUFFER_MODULE_0);

        assertEq(pufferProtocol.getPendingValidatorIndex(PUFFER_MODULE_0), 5, "next pending validator index");

        bytes[] memory signatures = _getGuardianSignatures(zeroPubKey);

        // 1. provision zero key
        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(zeroPubKey, 0, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        bytes[] memory bobSignatures = _getGuardianSignatures(bobPubKey);

        // Provision Bob that is not zero pubKey
        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(bobPubKey, 1, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(bobSignatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        Validator memory bobValidator = pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 1);

        assertTrue(bobValidator.status == Status.ACTIVE, "bob should be active");

        pufferProtocol.skipProvisioning(PUFFER_MODULE_0, _getGuardianSignaturesForSkipping());

        signatures = _getGuardianSignatures(zeroPubKey);

        emit SuccessfullyProvisioned(zeroPubKey, 3, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);

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

        _registerValidatorKey(bytes32("bob"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("charlie"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("david"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("emma"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("benjamin"), EIGEN_DA);
        _registerValidatorKey(bytes32("rocky"), CRAZY_GAINS);

        (bytes32 nextModule, uint256 nextId) = pufferProtocol.getNextValidatorToProvision();

        assertTrue(nextModule == PUFFER_MODULE_0, "module selection");
        assertTrue(nextId == 0, "module selection");

        bytes[] memory signatures = _getGuardianSignatures(_getPubKey(bytes32("bob")));

        // Provision Bob that is not zero pubKey
        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(_getPubKey(bytes32("bob")), 0, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        assertTrue(nextModule == EIGEN_DA, "module selection");
        // Id is zero, because that is the first in this queue
        assertTrue(nextId == 0, "module id");

        signatures = _getGuardianSignatures(_getPubKey(bytes32("benjamin")));

        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(_getPubKey(bytes32("benjamin")), 0, EIGEN_DA);
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        // // Because the EIGEN_DA queue is empty, the next for provisioning is from CRAZY_GAINS
        assertTrue(nextModule == CRAZY_GAINS, "module selection");
        assertTrue(nextId == 0, "module id");

        vm.stopPrank();

        // Now jason registers to EIGEN_DA
        _registerValidatorKey(bytes32("jason"), EIGEN_DA);

        // If we query next validator, it should switch back to EIGEN_DA (because of the weighted selection)
        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        assertTrue(nextModule == EIGEN_DA, "module selection");
        assertTrue(nextId == 1, "module id");

        // Provisioning of rocky should fail, because jason is next in line
        signatures = _getGuardianSignatures(_getPubKey(bytes32("rocky")));
        vm.expectRevert(Unauthorized.selector);
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        signatures = _getGuardianSignatures(_getPubKey(bytes32("jason")));

        // Provision Jason
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        signatures = _getGuardianSignatures(_getPubKey(bytes32("rocky")));

        // Rocky is now in line
        assertTrue(nextModule == CRAZY_GAINS, "module selection");
        assertTrue(nextId == 0, "module id");
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        (nextModule, nextId) = pufferProtocol.getNextValidatorToProvision();

        assertTrue(nextModule == PUFFER_MODULE_0, "module selection");
        assertTrue(nextId == 1, "module id");

        assertEq(
            pufferProtocol.getNextValidatorToBeProvisionedIndex(PUFFER_MODULE_0), 1, "next idx for no restaking module"
        );

        signatures = _getGuardianSignatures(_getPubKey(bytes32("alice")));

        vm.expectEmit(true, true, true, true);
        emit SuccessfullyProvisioned(_getPubKey(bytes32("alice")), 1, PUFFER_MODULE_0);
        pufferProtocol.provisionNode(signatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);
    }

    function test_create_puffer_module() public {
        bytes32 name = bytes32("LEVERAGED_RESTAKING");
        pufferProtocol.createPufferModule(name);
        IPufferModule module = IPufferModule(pufferProtocol.getModuleAddress(name));
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
    function test_register_validator_with_huge_commitment() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));

        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        vm.expectRevert();
        pufferProtocol.registerValidatorKey{ value: type(uint256).max }(
            validatorKeyData, PUFFER_MODULE_0, emptyPermit, emptyPermit
        );
    }

    // Node operator can deposit Bond in pufETH
    function test_register_pufETH_approve_buy_VT() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));
        vm.deal(alice, 10 ether);

        uint256 expectedMint = pufferVault.previewDeposit(1 ether);
        assertGt(expectedMint, 0, "should expect more pufETH");

        // Alice mints 1 ETH of pufETH
        vm.startPrank(alice);
        uint256 minted = pufferVault.depositETH{ value: 1 ether }(alice);
        assertGt(minted, 0, "should mint pufETH");

        // approve pufETH to pufferProtocol
        pufferVault.approve(address(pufferProtocol), type(uint256).max);

        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 0, "zero pufETH before");
        assertEq(pufferVault.balanceOf(alice), 1 ether, "1 pufETH before for alice");

        // In this case, the only important data on permit is the amount
        // Permit call will fail, but the amount is reused
        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);
        Permit memory permit;
        permit.amount = pufferVault.balanceOf(alice);

        // Get the smoothing commitment amount for 180 days
        uint256 sc = pufferOracle.getValidatorTicketPrice() * 180;

        // Register validator key by paying SC in ETH and depositing bond in pufETH
        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0, true);
        pufferProtocol.registerValidatorKey{ value: sc }(data, PUFFER_MODULE_0, permit, emptyPermit);
        // Alice has some dust in her wallet, because VT purchase changes the exchange rate, meaning pufETH is worth more
        assertEq(pufferVault.balanceOf(alice), 1696417975049392, "1696417975049392 pufETH after for alice");
        uint256 protocolPufETHBalance = pufferVault.balanceOf(address(pufferProtocol));
        assertApproxEqRel(protocolPufETHBalance, 0.998303582024950608 ether, pointZeroZeroTwo, "~0.998 pufETH after");
        assertApproxEqRel(
            pufferVault.convertToAssets(protocolPufETHBalance), 1 ether, pointZeroZeroOne, "1 ETH worth of pufETH after"
        );
    }

    // Node operator can deposit Bond with Permit and pay for the VT in ETH
    function test_register_pufETH_permit_pay_VT() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));
        vm.deal(alice, 10 ether);

        // Alice mints 1 ETH of pufETH
        vm.startPrank(alice);
        pufferVault.depositETH{ value: 1 ether }(alice);

        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 0, "zero pufETH before");
        assertEq(pufferVault.balanceOf(alice), 1 ether, "1 pufETH before for alice");

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);
        // Generate Permit data for 2 pufETH to the protocol
        Permit memory permit = _signPermit(
            _testTemps("alice", address(pufferProtocol), 2 ether, block.timestamp), pufferVault.DOMAIN_SEPARATOR()
        );

        uint256 numberOfDays = 180;
        // Get the smoothing commitment amount for 6 months
        uint256 sc = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        // Register validator key by paying SC in ETH and depositing bond in pufETH
        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0, true);
        pufferProtocol.registerValidatorKey{ value: sc }(data, PUFFER_MODULE_0, permit, emptyPermit);

        // Alice has some dust in her wallet, because VT purchase changes the exchange rate, meaning pufETH is worth more
        assertEq(pufferVault.balanceOf(alice), 1696417975049392, "1696417975049392 pufETH after for alice");

        uint256 protocolPufETHBalance = pufferVault.balanceOf(address(pufferProtocol));
        assertEq(protocolPufETHBalance, 0.998303582024950608 ether, "~0.99 pufETH after");
        assertApproxEqRel(
            pufferVault.convertToAssets(protocolPufETHBalance), 1 ether, pointZeroZeroOne, "1 ETH worth of pufETH after"
        );
    }

    // Node operator can deposit both VT and pufETH with Permit
    function test_register_both_permit() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));
        vm.deal(alice, 10 ether);

        uint256 numberOfDays = 200;
        uint256 amount = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        // Alice mints 1 ETH of pufETH
        vm.startPrank(alice);
        // Purchase pufETH
        pufferVault.depositETH{ value: 1 ether }(alice);
        // Alice purchases VT
        validatorTicket.purchaseValidatorTicket{ value: amount }(alice);

        // Because Alice purchased a lot of VT's, it changed the conversion rate
        // Because of that the registerValidatorKey will .transferFrom a smaller amount of pufETH
        uint256 leftOverPufETH = pufferVault.balanceOf(alice) - pufferVault.convertToShares(1 ether);

        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 0, "zero pufETH before");
        assertEq(pufferVault.balanceOf(alice), 1 ether, "1 pufETH before for alice");
        assertEq(validatorTicket.balanceOf(alice), _upscaleTo18Decimals(numberOfDays), "VT before for alice");

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        uint256 bond = 1 ether;
        Permit memory pufETHPermit = _signPermit(
            _testTemps("alice", address(pufferProtocol), bond, block.timestamp), pufferVault.DOMAIN_SEPARATOR()
        );
        Permit memory vtPermit = _signPermit(
            _testTemps("alice", address(pufferProtocol), _upscaleTo18Decimals(numberOfDays), block.timestamp),
            validatorTicket.DOMAIN_SEPARATOR()
        );

        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0, true);
        pufferProtocol.registerValidatorKey(data, PUFFER_MODULE_0, pufETHPermit, vtPermit);

        assertEq(pufferVault.balanceOf(alice), leftOverPufETH, "alice should have some leftover pufETH");
        assertEq(validatorTicket.balanceOf(alice), 0, "0 vt after for alice");
        assertApproxEqRel(pufferVault.balanceOf(address(pufferProtocol)), bond, 0.002e18, "1 pufETH after");
    }

    // Node operator can deposit both VT and pufETH with .approve
    function test_register_both_approve() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));
        vm.deal(alice, 10 ether);

        uint256 numberOfDays = 200;
        uint256 amount = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        vm.startPrank(alice);
        // Alice purchases VT
        validatorTicket.purchaseValidatorTicket{ value: amount }(alice);
        // Alice mints 1 ETH of pufETH
        pufferVault.depositETH{ value: 1 ether }(alice);

        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 0, "zero pufETH before");
        // 1 wei diff
        assertApproxEqAbs(
            pufferVault.convertToAssets(pufferVault.balanceOf(alice)), 1 ether, 1, "1 pufETH before for alice"
        );
        assertEq(validatorTicket.balanceOf(alice), _upscaleTo18Decimals(numberOfDays), "VT before for alice");

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        uint256 bond = 1 ether;

        pufferVault.approve(address(pufferProtocol), type(uint256).max);
        validatorTicket.approve(address(pufferProtocol), type(uint256).max);

        Permit memory vtPermit = emptyPermit;
        vtPermit.amount = _upscaleTo18Decimals(numberOfDays); // upscale to 18 decimals

        Permit memory pufETHPermit = emptyPermit;
        pufETHPermit.amount = pufferVault.convertToShares(bond);

        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0, true);
        pufferProtocol.registerValidatorKey(data, PUFFER_MODULE_0, pufETHPermit, vtPermit);

        assertEq(pufferVault.balanceOf(alice), 0, "0 pufETH after for alice");
        assertEq(validatorTicket.balanceOf(alice), 0, "0 vt after for alice");
        // 1 wei diff
        assertApproxEqAbs(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))), bond, 1, "1 pufETH after"
        );
    }

    // Node operator can pay for pufETH with ETH and use Permit for VT
    function test_register_pufETH_pay_vt_approve() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));
        vm.deal(alice, 10 ether);

        uint256 numberOfDays = 30;
        uint256 amount = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        vm.startPrank(alice);
        // Alice purchases VT
        validatorTicket.purchaseValidatorTicket{ value: amount }(alice);

        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 0, "zero pufETH before");
        assertEq(pufferVault.balanceOf(alice), 0, "0 pufETH before for alice");
        assertEq(validatorTicket.balanceOf(alice), _upscaleTo18Decimals(numberOfDays), "VT before for alice");

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);
        Permit memory permit = _signPermit(
            _testTemps("alice", address(pufferProtocol), _upscaleTo18Decimals(numberOfDays), block.timestamp),
            validatorTicket.DOMAIN_SEPARATOR()
        );

        // Alice is using SGX
        uint256 bond = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0, true);
        pufferProtocol.registerValidatorKey{ value: bond }(data, PUFFER_MODULE_0, emptyPermit, permit);

        assertEq(pufferVault.balanceOf(alice), 0, "0 pufETH after for alice");
        assertApproxEqRel(pufferVault.balanceOf(address(pufferProtocol)), 1 ether, pointZeroFive, "~1 pufETH after");
    }

    // Node operator can deposit Bond in pufETH
    function test_register_validator_key_with_permit_reverts_invalid_vt_amount() external {
        bytes memory pubKey = _getPubKey(bytes32("alice"));
        vm.deal(alice, 100 ether);

        // Alice mints 2 ETH of pufETH
        vm.startPrank(alice);
        pufferVault.depositETH{ value: 2 ether }(alice);

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);
        // Generate Permit data for 10 pufETH to the protocol
        Permit memory permit = _signPermit(
            _testTemps("alice", address(pufferProtocol), 0.5 ether, block.timestamp), pufferVault.DOMAIN_SEPARATOR()
        );

        // Underpay VT
        vm.expectRevert();
        pufferProtocol.registerValidatorKey{ value: 0.1 ether }(data, PUFFER_MODULE_0, permit, emptyPermit);
    }

    function test_validator_griefing_attack() external {
        vm.deal(address(pufferVault), 100 ether);

        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        bytes[] memory guardianSignatures = _getGuardianSignatures(_getPubKey(bytes32("alice")));
        // Register and provision Alice
        // Alice may be an active validator or it can be exited, doesn't matter
        pufferProtocol.provisionNode(guardianSignatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);

        // Register another validator with using the same data
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);

        // Try to provision it with the original message (replay attack)
        // It should revert
        vm.expectRevert(Unauthorized.selector);
        pufferProtocol.provisionNode(guardianSignatures, _validatorSignature(), DEFAULT_DEPOSIT_ROOT);
    }

    function test_validator_limit_per_module() external {
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorLimitPerModuleChanged(500, 1);
        pufferProtocol.setValidatorLimitPerModule(PUFFER_MODULE_0, 1);

        // Revert if the registration will be over the limit
        uint256 smoothingCommitment = pufferOracle.getValidatorTicketPrice();
        bytes memory pubKey = _getPubKey(bytes32("bob"));
        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);
        uint256 bond = 1 ether;

        vm.expectRevert(IPufferProtocol.ValidatorLimitForModuleReached.selector);
        pufferProtocol.registerValidatorKey{ value: (smoothingCommitment + bond) }(
            validatorKeyData, PUFFER_MODULE_0, emptyPermit, emptyPermit
        );
    }

    function test_claim_bond_for_single_withdrawal() external {
        uint256 startTimestamp = 1707411226;

        // Alice registers one validator and we provision it
        vm.deal(alice, 2 ether);
        vm.deal(NoRestakingModule, 200 ether);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        assertApproxEqAbs(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1 ether,
            1,
            "~1 pufETH in protocol"
        );

        // bond + something for the validator registration
        assertEq(address(pufferVault).balance, 1001.2835 ether, "vault eth balance");

        Validator memory validator = pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 0);

        assertEq(validator.bond, pufferVault.balanceOf(address(pufferProtocol)), "alice bond is in the protocol");

        vm.warp(startTimestamp);

        pufferProtocol.provisionNode(
            _getGuardianSignatures(_getPubKey(bytes32("alice"))), _validatorSignature(), DEFAULT_DEPOSIT_ROOT
        );

        // Didn't claim the bond yet
        assertEq(pufferVault.balanceOf(alice), 0, "alice has zero pufETH");

        // 15 days later (+16 is because 1 day is the start offset)
        vm.warp(startTimestamp + 16 days);

        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            module: NoRestakingModule,
            moduleName: PUFFER_MODULE_0,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            startEpoch: 100,
            endEpoch: _getEpochNumber(16 days, 100),
            wasSlashed: false
        });

        // Valid proof
        _executeFullWithdrawal(validatorInfo);

        // Alice got the pufETH
        assertEq(pufferVault.balanceOf(alice), validator.bond, "alice got the pufETH");
        // 1 wei diff
        assertApproxEqAbs(
            pufferVault.convertToAssets(pufferVault.balanceOf(alice)), 1 ether, 1, "assets owned by alice"
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
        assertEq(pufferProtocol.getMinimumVtAmount(), 28 ether, "initial value");

        vm.startPrank(DAO);
        pufferProtocol.changeMinimumVTAmount(50 ether);

        assertEq(pufferProtocol.getMinimumVtAmount(), 50 ether, "value after change");
    }

    // Alice tries to withdraw all VT before provisioning
    function test_withdraw_vt_before_provisioning() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);

        // Register Validator key registers validator with 30 VTs
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);

        vm.expectRevert(IPufferProtocol.ActiveOrPendingValidatorsExist.selector);
        pufferProtocol.withdrawValidatorTickets(30 ether, alice);
    }

    function test_register_skip_provision_withdraw_vt() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);

        assertApproxEqRel(
            pufferProtocol.getValidatorTicketsBalance(alice), 30 ether, pointZeroZeroOne, "alice should have ~30 VTS"
        );

        vm.stopPrank();
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.NumberOfRegisteredValidatorsChanged(PUFFER_MODULE_0, 0);
        pufferProtocol.skipProvisioning(PUFFER_MODULE_0, _getGuardianSignaturesForSkipping());

        assertApproxEqRel(
            pufferProtocol.getValidatorTicketsBalance(alice),
            20 ether,
            pointZeroZeroOne,
            "alice should have ~20 VTS -10 penalty"
        );

        vm.startPrank(alice);
        pufferProtocol.withdrawValidatorTickets(uint96(20 ether), alice);

        assertEq(validatorTicket.balanceOf(alice), 20 ether, "alice got her VT");
    }

    function test_setVTPenalty() public {
        assertEq(pufferProtocol.getVTPenalty(), 10 ether, "initial value");

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.VTPenaltyChanged(10 ether, 20 ether);
        pufferProtocol.setVTPenalty(20 ether);

        assertEq(pufferProtocol.getVTPenalty(), 20 ether, "value after change");
    }

    function test_setVTPenalty_bigger_than_minimum_VT_amount() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferProtocol.InvalidVTAmount.selector);
        pufferProtocol.setVTPenalty(50 ether);
    }

    function test_changeMinimumVTAmount_lower_than_penalty() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferProtocol.InvalidVTAmount.selector);
        pufferProtocol.changeMinimumVTAmount(9 ether);
    }

    function test_new_vtPenalty_works() public {
        // sets VT penalty to 20
        test_setVTPenalty();

        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        assertApproxEqRel(
            pufferProtocol.getValidatorTicketsBalance(alice), 30 ether, pointZeroZeroOne, "alice should have ~30 VTS"
        );

        pufferProtocol.skipProvisioning(PUFFER_MODULE_0, _getGuardianSignaturesForSkipping());

        // Alice loses 20 VT's
        assertApproxEqRel(
            pufferProtocol.getValidatorTicketsBalance(alice), 10 ether, pointZeroZeroOne, "alice should have ~20 VTS"
        );

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        // Alice is not provisioned
        assertApproxEqRel(
            pufferProtocol.getValidatorTicketsBalance(alice), 40 ether, pointZeroZeroOne, "alice should have ~40 VTS"
        );

        // Set penalty to 0
        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.VTPenaltyChanged(20 ether, 0);
        pufferProtocol.setVTPenalty(0);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        assertApproxEqRel(
            pufferProtocol.getValidatorTicketsBalance(alice),
            70 ether,
            pointZeroZeroOne,
            "alice should have ~70 VTS register"
        );

        pufferProtocol.skipProvisioning(PUFFER_MODULE_0, _getGuardianSignaturesForSkipping());

        assertApproxEqRel(
            pufferProtocol.getValidatorTicketsBalance(alice),
            70 ether,
            pointZeroZeroOne,
            "alice should have ~70 VTS end"
        );
    }

    function test_double_withdrawal_reverts() public {
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);

        assertEq(validatorTicket.balanceOf(address(pufferProtocol)), 30 ether, "protocol has 30 VT");
        assertApproxEqAbs(
            _getUnderlyingETHAmount(address(pufferProtocol)), 1 ether, 1, "protocol should have ~1 eth bond"
        );

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("alice")), 0, PUFFER_MODULE_0, 0, _getVTBurnAmount(100, _getEpochNumber(28 days, 100))
        );
        _executeFullWithdrawal(
            StoppedValidatorInfo({
                module: NoRestakingModule,
                moduleName: PUFFER_MODULE_0,
                pufferModuleIndex: 0,
                withdrawalAmount: 32 ether,
                startEpoch: 100,
                endEpoch: _getEpochNumber(28 days, 100),
                wasSlashed: false
            })
        );

        // 28 got burned from Alice
        assertApproxEqRel(
            validatorTicket.balanceOf(address(pufferProtocol)), 2 ether, pointZeroZeroOne, "Protocol has 2 VT"
        );

        assertApproxEqAbs(
            _getUnderlyingETHAmount(address(pufferProtocol)), 0 ether, 1, "protocol should have 0 eth bond"
        );

        assertApproxEqAbs(_getUnderlyingETHAmount(address(alice)), 1 ether, 1, "alice got back the bond");

        // We've removed the validator data, meaning the validator status is 0 (UNINITIALIZED)
        vm.expectRevert(abi.encodeWithSelector(IPufferProtocol.InvalidValidatorState.selector, 0));
        _executeFullWithdrawal(
            StoppedValidatorInfo({
                module: NoRestakingModule,
                moduleName: PUFFER_MODULE_0,
                pufferModuleIndex: 0,
                withdrawalAmount: 32 ether,
                startEpoch: 100,
                endEpoch: _getEpochNumber(28 days, 100),
                wasSlashed: false
            })
        );
    }

    // After full withdrawals the node operators claim the remaining VTs
    function test_vt_withdrawals_after_batch_claim() public {
        test_batch_claim();

        assertEq(validatorTicket.balanceOf(alice), 0, "0 vt alice before");

        uint256 aliceVTBalance = pufferProtocol.getValidatorTicketsBalance(alice);

        assertApproxEqRel(aliceVTBalance, 2 ether, pointZeroZeroOne, "2 vt balance after");

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorTicketsWithdrawn(alice, alice, aliceVTBalance);
        pufferProtocol.withdrawValidatorTickets(uint96(aliceVTBalance), alice);

        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 0, "0 vt balance after");
        assertEq(validatorTicket.balanceOf(alice), aliceVTBalance, "~20 vt alice before");

        uint256 bobVTBalance = pufferProtocol.getValidatorTicketsBalance(bob);

        assertApproxEqRel(bobVTBalance, 2 ether, pointZeroZeroOne, "2 vt balance before bob");

        vm.startPrank(bob);

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorTicketsWithdrawn(bob, alice, bobVTBalance);
        pufferProtocol.withdrawValidatorTickets(uint96(bobVTBalance), alice);

        assertEq(pufferProtocol.getValidatorTicketsBalance(bob), 0, "0 vt balance after bob");
        assertApproxEqRel(validatorTicket.balanceOf(alice), 4 ether, pointZeroZeroOne, "4 vt alice after bobs gift");
    }

    // Batch claim 32 ETH withdrawals
    function test_batch_claim() public {
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);
        _registerAndProvisionNode(bytes32("bob"), PUFFER_MODULE_0, bob);

        StoppedValidatorInfo memory aliceInfo = StoppedValidatorInfo({
            module: NoRestakingModule,
            moduleName: PUFFER_MODULE_0,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            startEpoch: 100,
            endEpoch: _getEpochNumber(28 days, 100),
            wasSlashed: false
        });

        StoppedValidatorInfo memory bobInfo = StoppedValidatorInfo({
            module: NoRestakingModule,
            moduleName: PUFFER_MODULE_0,
            pufferModuleIndex: 1,
            withdrawalAmount: 32 ether,
            startEpoch: 100,
            endEpoch: _getEpochNumber(28 days, 100),
            wasSlashed: false
        });

        StoppedValidatorInfo[] memory stopInfos = new StoppedValidatorInfo[](2);
        stopInfos[0] = aliceInfo;
        stopInfos[1] = bobInfo;

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("alice")), 0, PUFFER_MODULE_0, 0, _getVTBurnAmount(100, _getEpochNumber(28 days, 100))
        );
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("bob")), 1, PUFFER_MODULE_0, 0, _getVTBurnAmount(100, _getEpochNumber(28 days, 100))
        );
        pufferProtocol.batchHandleWithdrawals(stopInfos, _getHandleBatchWithdrawalMessage(stopInfos));

        assertApproxEqAbs(
            _getUnderlyingETHAmount(address(pufferProtocol)), 0 ether, 1, "protocol should have 0 eth bond"
        );

        // Alice got more because she earned the rewards from Bob's registration
        assertGe(_getUnderlyingETHAmount(address(alice)), 1 ether, "alice got back the bond gt");

        assertApproxEqAbs(_getUnderlyingETHAmount(address(bob)), 1 ether, 1, "bob got back the bond");
    }

    // Batch claim of different amounts
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
            startEpoch: 100,
            endEpoch: _getEpochNumber(35 days, 100),
            wasSlashed: false
        });
        stopInfos[1] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 1,
            withdrawalAmount: 31.9 ether,
            startEpoch: 100,
            endEpoch: _getEpochNumber(28 days, 100),
            wasSlashed: false
        });
        stopInfos[2] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 2,
            withdrawalAmount: 31 ether,
            startEpoch: 100,
            endEpoch: _getEpochNumber(34 days, 100),
            wasSlashed: true
        });
        stopInfos[3] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 3,
            withdrawalAmount: 31.8 ether,
            startEpoch: 100,
            endEpoch: _getEpochNumber(48 days, 100),
            wasSlashed: false
        });
        stopInfos[4] = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 4,
            withdrawalAmount: 31.5 ether,
            startEpoch: 100,
            endEpoch: _getEpochNumber(2 days, 100),
            wasSlashed: true
        });

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("alice")), 0, PUFFER_MODULE_0, 0, _getVTBurnAmount(100, _getEpochNumber(35 days, 100))
        );
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("bob")),
            1,
            PUFFER_MODULE_0,
            pufferVault.convertToSharesUp(0.1 ether),
            _getVTBurnAmount(100, _getEpochNumber(28 days, 100))
        );
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("charlie")),
            2,
            PUFFER_MODULE_0,
            pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 2).bond,
            _getVTBurnAmount(100, _getEpochNumber(34 days, 100))
        ); // got slashed
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("dianna")),
            3,
            PUFFER_MODULE_0,
            pufferVault.convertToSharesUp(0.2 ether),
            _getVTBurnAmount(100, _getEpochNumber(48 days, 100))
        );
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("eve")),
            4,
            PUFFER_MODULE_0,
            pufferProtocol.getValidatorInfo(PUFFER_MODULE_0, 4).bond,
            28 ether // minimum vt amount
        ); // got slashed
        pufferProtocol.batchHandleWithdrawals(stopInfos, _getHandleBatchWithdrawalMessage(stopInfos));

        assertApproxEqAbs(
            _getUnderlyingETHAmount(address(pufferProtocol)), 0 ether, 1, "protocol should have 0 eth bond"
        );

        // Alice got more because she earned the rewards from the others
        assertGe(_getUnderlyingETHAmount(address(alice)), 1 ether, "alice got back the bond gt");

        // Bob got 0.9 ETH bond + some rewards from the others
        assertGe(_getUnderlyingETHAmount(address(bob)), 0.9 ether, "bob got back the bond gt");

        // Charlie got 0 bond
        assertEq(_getUnderlyingETHAmount(address(charlie)), 0, "charlie got 0 bond - slashed");

        assertGe(_getUnderlyingETHAmount(address(dianna)), 0.8 ether, "dianna got back the bond gt");

        assertEq(_getUnderlyingETHAmount(address(eve)), 0, "eve got 0 bond - slashed");
    }

    function test_single_withdrawal() public {
        _registerAndProvisionNode(bytes32("alice"), PUFFER_MODULE_0, alice);
        _registerAndProvisionNode(bytes32("bob"), PUFFER_MODULE_0, bob);

        StoppedValidatorInfo memory aliceInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            withdrawalAmount: 32 ether,
            startEpoch: 100,
            endEpoch: _getEpochNumber(28 days, 100),
            wasSlashed: false
        });

        StoppedValidatorInfo memory bobInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 1,
            withdrawalAmount: 32 ether,
            startEpoch: 100,
            endEpoch: _getEpochNumber(28 days, 100),
            wasSlashed: false
        });

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("alice")), 0, PUFFER_MODULE_0, 0, _getVTBurnAmount(100, _getEpochNumber(28 days, 100))
        ); // 10 days of VT
        _executeFullWithdrawal(aliceInfo);
        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorExited(
            _getPubKey(bytes32("bob")), 1, PUFFER_MODULE_0, 0, _getVTBurnAmount(100, _getEpochNumber(28 days, 100))
        ); // 10 days of VT
        _executeFullWithdrawal(bobInfo);

        assertApproxEqAbs(
            _getUnderlyingETHAmount(address(pufferProtocol)), 0 ether, 1, "protocol should have 0 eth bond"
        );

        // Alice got more because she earned the rewards from Bob's registration
        assertGe(_getUnderlyingETHAmount(address(alice)), 1 ether, "alice got back the bond gt");

        assertApproxEqAbs(_getUnderlyingETHAmount(address(bob)), 1 ether, 1, "bob got back the bond");
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
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToShares(1 ether);
        assertEq(exchangeRateBefore, 999433604122689216, "shares before provisioning");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(
            _getGuardianSignatures(_getPubKey(bytes32("alice"))), _validatorSignature(), DEFAULT_DEPOSIT_ROOT
        );

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
            startEpoch: 100,
            endEpoch: _getEpochNumber(28 days, 100),
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
            1 ether,
            pointZeroOne,
            "1 ETH worth of pufETH in the protocol"
        );
        assertEq(pufferVault.balanceOf(alice), 0, "0 pufETH alice");
    }

    // Register 2 validators, provision 1, slash 1.5 whole validator bond owned by node operator
    // Case 2
    function test_slashing_case_2() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToShares(1 ether);
        assertEq(exchangeRateBefore, 999433604122689216, "shares before provisioning");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(
            _getGuardianSignatures(_getPubKey(bytes32("alice"))), _validatorSignature(), DEFAULT_DEPOSIT_ROOT
        );

        vm.deal(NoRestakingModule, 200 ether);

        // Now the node operators submit proofs to get back their bond
        vm.startPrank(alice);
        // Invalid block number = invalid proof
        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            startEpoch: 100,
            endEpoch: _getEpochNumber(28 days, 100),
            withdrawalAmount: 30.5 ether,
            wasSlashed: true
        });

        // Burns one whole bond
        _executeFullWithdrawal(validatorInfo);

        // 1 ETH gives you more pufETH after the `retrieveBond` call, meaning it is worse than before
        assertLt(exchangeRateBefore, pufferVault.convertToShares(1 ether), "shares after retrieve");

        // The other validator has less than 1 ETH in the bond
        // Bad dept is shared between all pufETH holders
        assertApproxEqRel(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1 ether,
            pointZeroOne,
            "1 ether ETH worth of pufETH in the protocol"
        );
        assertEq(pufferVault.balanceOf(alice), 0, "0 pufETH alice");
    }

    // Register 2 validators, provision 1, slash 1 whole validator bond (1 ETH)
    // Case 3
    function test_slashing_case_3() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToShares(1 ether);
        assertEq(exchangeRateBefore, 999433604122689216, "shares before provisioning");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(
            _getGuardianSignatures(_getPubKey(bytes32("alice"))), _validatorSignature(), DEFAULT_DEPOSIT_ROOT
        );

        vm.deal(NoRestakingModule, 200 ether);

        // Now the node operators submit proofs to get back their bond
        vm.startPrank(alice);
        // Invalid block number = invalid proof
        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            startEpoch: 100,
            endEpoch: _getEpochNumber(28 days, 100),
            withdrawalAmount: 31 ether,
            wasSlashed: true
        });

        // Burns one whole bond
        _executeFullWithdrawal(validatorInfo);

        // Exchange rate remains the same, it is slightly better
        assertApproxEqRel(
            exchangeRateBefore, pufferVault.convertToShares(1 ether), pointZeroZeroOne, "shares after retrieve"
        );
        // 1 ETH gives you less pufETH after the `retrieveBond` call, meaning it is better than before (slightly)
        assertGt(exchangeRateBefore, pufferVault.convertToShares(1 ether), "shares after retrieve");

        // Alice has a little over 1 ETH because she earned something for paying the VT on the second validator registration
        assertApproxEqRel(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1 ether,
            pointZeroZeroOne,
            "1 ETH worth of pufETH in the protocol"
        );
        assertGt(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1 ether,
            "1 ETH worth of pufETH in the protocol gt"
        );
        assertEq(pufferVault.balanceOf(alice), 0, "0 pufETH alice");
    }

    // Register 2 validators, provision 1, no slashing, but validator was offline and lost 0.1 ETH
    // Case 4
    function test_slashing_case_4() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToShares(1 ether);
        assertEq(exchangeRateBefore, 999433604122689216, "shares before provisioning");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(
            _getGuardianSignatures(_getPubKey(bytes32("alice"))), _validatorSignature(), DEFAULT_DEPOSIT_ROOT
        );

        vm.deal(NoRestakingModule, 200 ether);

        // Now the node operators submit proofs to get back their bond
        vm.startPrank(alice);
        // Invalid block number = invalid proof
        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            startEpoch: 100,
            endEpoch: _getEpochNumber(28 days, 100),
            withdrawalAmount: 31.9 ether,
            wasSlashed: false
        });

        // Burns one whole bond
        _executeFullWithdrawal(validatorInfo);

        // Exchange rate stays the same
        assertEq(exchangeRateBefore, pufferVault.convertToShares(1 ether), "shares after retrieve");

        // Alice has ~ 1 ETH locked in the protocol
        assertApproxEqRel(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1 ether,
            pointZeroZeroOne,
            "1 ETH worth of pufETH in the protocol"
        );
        // Alice got a little over 0.9 ETH worth of pufETH because she earned something for paying the VT on the second validator registration
        assertGt(pufferVault.convertToAssets(pufferVault.balanceOf(alice)), 0.9 ether, ">0.9 ETH worth of pufETH alice");
    }

    // Register 2 validators, provision 1, no slashing, validator exited with 32.1 ETH
    // Case 5
    function test_slashing_case_5() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        // Get the exchange rate before provisioning validators
        uint256 exchangeRateBefore = pufferVault.convertToShares(1 ether);
        assertEq(exchangeRateBefore, 999433604122689216, "shares before provisioning");

        uint256 startTimestamp = 1707411226;
        vm.warp(startTimestamp);
        pufferProtocol.provisionNode(
            _getGuardianSignatures(_getPubKey(bytes32("alice"))), _validatorSignature(), DEFAULT_DEPOSIT_ROOT
        );

        vm.deal(NoRestakingModule, 200 ether);

        // Now the node operators submit proofs to get back their bond
        vm.startPrank(alice);
        // Invalid block number = invalid proof
        StoppedValidatorInfo memory validatorInfo = StoppedValidatorInfo({
            moduleName: PUFFER_MODULE_0,
            module: NoRestakingModule,
            pufferModuleIndex: 0,
            startEpoch: 100,
            endEpoch: _getEpochNumber(15 days, 100),
            withdrawalAmount: 32.1 ether,
            wasSlashed: false
        });

        // Burns one whole bond
        _executeFullWithdrawal(validatorInfo);

        // Exchange rate stays the same
        assertEq(exchangeRateBefore, pufferVault.convertToShares(1 ether), "shares after retrieve");

        // Alice has ~ 1 ETH locked in the protocol
        assertApproxEqRel(
            pufferVault.convertToAssets(pufferVault.balanceOf(address(pufferProtocol))),
            1 ether,
            pointZeroZeroOne,
            "1 ETH worth of pufETH in the protocol"
        );
        // Alice got a little over 1 ETH worth of pufETH because she earned something for paying the VT on the second validator registration
        assertGt(pufferVault.convertToAssets(pufferVault.balanceOf(alice)), 1 ether, ">1 ETH worth of pufETH alice");
    }

    function test_validator_early_exit_dos() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        pufferProtocol.provisionNode(
            _getGuardianSignatures(_getPubKey(bytes32("alice"))), _validatorSignature(), DEFAULT_DEPOSIT_ROOT
        );

        // Alice exited after 1 day
        _executeFullWithdrawal(
            StoppedValidatorInfo({
                module: NoRestakingModule,
                moduleName: PUFFER_MODULE_0,
                pufferModuleIndex: 0,
                withdrawalAmount: 32 ether,
                startEpoch: 100,
                endEpoch: _getEpochNumber(1 days, 100),
                wasSlashed: false
            })
        );

        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 2 ether, "alice got 2 VT left in the protocol");
    }

    // Alice registers one 30 VT validator
    // DAO changes the minimum VT amount to 35
    // Alice the validator after 3 days
    function test_validator_early_exit_edge_case() public {
        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        _registerValidatorKey(bytes32("alice"), PUFFER_MODULE_0);
        vm.stopPrank();

        pufferProtocol.provisionNode(
            _getGuardianSignatures(_getPubKey(bytes32("alice"))), _validatorSignature(), DEFAULT_DEPOSIT_ROOT
        );

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
                startEpoch: 100,
                endEpoch: _getEpochNumber(3 days, 100),
                wasSlashed: false
            })
        );

        assertEq(pufferProtocol.getValidatorTicketsBalance(alice), 0 ether, "alice got 0 VT left in the protocol");
    }

    // User purchases a lot of VT using ETH, but uses Permit to transfer pufETH
    function test_purchase_big_amount_of_vt() public {
        bytes memory pubKey = _getPubKey(bytes32("alice"));
        vm.deal(alice, 10 ether);

        // Alice mints 1 ETH of pufETH
        vm.startPrank(alice);
        pufferVault.depositETH{ value: 1 ether }(alice);

        assertEq(pufferVault.balanceOf(address(pufferProtocol)), 0, "zero pufETH before");
        assertEq(pufferVault.balanceOf(alice), 1 ether, "1 pufETH before for alice");

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        // Generate Permit data for 1 pufETH to the protocol
        Permit memory permit = _signPermit(
            _testTemps("alice", address(pufferProtocol), 1 ether, block.timestamp), pufferVault.DOMAIN_SEPARATOR()
        );

        // Register validator key by paying SC in ETH and depositing bond in pufETH
        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, 0, PUFFER_MODULE_0, true);
        pufferProtocol.registerValidatorKey{ value: 9 ether }(data, PUFFER_MODULE_0, permit, emptyPermit);

        // Because alice purchased VT in the registration TX, it modified the exchange rate and we take less pufETH from her.
        assertEq(pufferVault.balanceOf(alice), 8424921124709635, "alice has 8424921124709635 pufETH after registering");
    }

    // Alice uses Permit for VT and pays for the bond with ETH, but sends more ETH than needed
    function test_revert_for_excess_eth() public {
        bytes memory pubKey = _getPubKey(bytes32("alice"));
        vm.deal(alice, 10 ether);

        uint256 numberOfDays = 30;
        uint256 amount = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        // Alice mints 1 ETH of pufETH
        vm.startPrank(alice);
        // Alice purchases VT
        validatorTicket.purchaseValidatorTicket{ value: amount }(alice);

        Permit memory vtPermit = _signPermit(
            _testTemps("alice", address(pufferProtocol), _upscaleTo18Decimals(numberOfDays), block.timestamp),
            validatorTicket.DOMAIN_SEPARATOR()
        );

        ValidatorKeyData memory data = _getMockValidatorKeyData(pubKey, PUFFER_MODULE_0);

        // User pays for the bond in pufETH, but decides to send more than the bond 1.1 eth
        vm.expectRevert(IPufferProtocol.InvalidETHAmount.selector);
        pufferProtocol.registerValidatorKey{ value: 1.1 ether }(data, PUFFER_MODULE_0, emptyPermit, vtPermit);
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

    function _getGuardianSignatures(bytes memory pubKey) internal view returns (bytes[] memory) {
        (bytes32 moduleName, uint256 pendingIdx) = pufferProtocol.getNextValidatorToProvision();
        Validator memory validator = pufferProtocol.getValidatorInfo(moduleName, pendingIdx);
        // If there is no module return empty byte array
        if (validator.module == address(0)) {
            return new bytes[](0);
        }
        bytes memory withdrawalCredentials = pufferProtocol.getWithdrawalCredentials(validator.module);

        bytes32 digest = LibGuardianMessages._getBeaconDepositMessageToBeSigned(
            pendingIdx,
            pubKey,
            _validatorSignature(),
            withdrawalCredentials,
            pufferProtocol.getDepositDataRoot({
                pubKey: pubKey,
                signature: _validatorSignature(),
                withdrawalCredentials: withdrawalCredentials
            })
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guardian1SKEnclave, digest);
        bytes memory signature1 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian2SKEnclave, digest);
        (v, r, s) = vm.sign(guardian3SKEnclave, digest);
        bytes memory signature2 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian3SKEnclave, digest);
        bytes memory signature3 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        bytes[] memory guardianSignatures = new bytes[](3);
        guardianSignatures[0] = signature1;
        guardianSignatures[1] = signature2;
        guardianSignatures[2] = signature3;

        return guardianSignatures;
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

    // Generates a mock validator data for SGX 1 ETH case
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
            blsEncryptedPrivKeyShares: new bytes[](3),
            blsPubKeySet: new bytes(48),
            raveEvidence: bytes("mock rave") // Guardians are checking it off chain
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
     */
    function _registerValidatorKey(bytes32 pubKeyPart, bytes32 moduleName) internal {
        uint256 numberOfDays = 30;
        uint256 vtPrice = pufferOracle.getValidatorTicketPrice() * numberOfDays;
        bytes memory pubKey = _getPubKey(pubKeyPart);
        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, moduleName);
        uint256 idx = pufferProtocol.getPendingValidatorIndex(moduleName);

        uint256 bond = 1 ether;

        // Empty permit means that the node operator is paying with ETH for both bond & VT in the registration transaction
        vm.expectEmit(true, true, true, true);
        emit ValidatorKeyRegistered(pubKey, idx, moduleName, true);
        pufferProtocol.registerValidatorKey{ value: (vtPrice + bond) }(
            validatorKeyData, moduleName, emptyPermit, emptyPermit
        );
    }

    /**
     * @dev Registers and provisions a new validator with 1 ETH bond (enclave) and 30 VTs (see _registerValidatorKey)
     */
    function _registerAndProvisionNode(bytes32 pubKeyPart, bytes32 moduleName, address nodeOperator) internal {
        vm.deal(nodeOperator, 10 ether);

        vm.startPrank(nodeOperator);
        _registerValidatorKey(pubKeyPart, moduleName);
        vm.stopPrank();

        pufferProtocol.provisionNode(
            _getGuardianSignatures(_getPubKey(pubKeyPart)), _validatorSignature(), DEFAULT_DEPOSIT_ROOT
        );
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

    function _getEpochNumber(uint256 validationTimeInSeconds, uint256 startEpoch)
        internal
        pure
        returns (uint256 endEpoch)
    {
        uint256 secondsInEpoch = 32 * 12;
        uint256 numberOfEpochs = validationTimeInSeconds / secondsInEpoch;
        return startEpoch + numberOfEpochs;
    }

    function _getVTBurnAmount(uint256 startEpoch, uint256 endEpoch) internal pure returns (uint256) {
        uint256 validatedEpochs = endEpoch - startEpoch;
        // Epoch has 32 blocks, each block is 12 seconds, we upscale to 18 decimals to get the VT amount and divide by 1 day
        // The formula is validatedEpochs * 32 * 12 * 1 ether / 1 days (4444444444444444.44444444...) we round it up
        return validatedEpochs * 4444444444444445;
    }
}

struct MerkleProofData {
    bytes32 moduleName;
    uint256 index;
    uint256 amount;
    uint8 wasSlashed;
}
