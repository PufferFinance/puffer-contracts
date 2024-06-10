// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferModule } from "../../src/interface/IPufferModule.sol";
import { IPufferProtocol } from "../../src/interface/IPufferProtocol.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { RaveEvidence } from "../../src/struct/RaveEvidence.sol";
import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { PufferVaultV2 } from "../../src/PufferVaultV2.sol";
import { stETHMock } from "../mocks/stETHMock.sol";
import { ValidatorKeyData } from "../../src/struct/ValidatorKeyData.sol";
import { Validator } from "../../src/struct/Validator.sol";
import { Status } from "../../src/struct/Status.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { LibGuardianMessages } from "../../src/LibGuardianMessages.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { Merkle } from "murky/Merkle.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { ROLE_ID_PUFFER_PROTOCOL } from "script/SetupAccess.s.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { IValidatorTicket } from "../../src/interface/IValidatorTicket.sol";
import { PufferOracleV2 } from "../../src/PufferOracleV2.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";

struct ProvisionedValidator {
    bytes32 moduleName;
    uint256 idx;
}

contract PufferProtocolHandler is Test {
    using SafeERC20 for address;
    using Address for address payable;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Guardians are preset for the test environment, and these are the enclave secret keys
    uint256 guardian1SKEnclave = 81165043675487275545095207072241430673874640255053335052777448899322561824201;
    address guardian1Enclave = vm.addr(guardian1SKEnclave);
    uint256 guardian2SKEnclave = 90480947395980135991870782913815514305328820213706480966227475230529794843518;
    address guardian2Enclave = vm.addr(guardian2SKEnclave);
    uint256 guardian3SKEnclave = 56094429399408807348734910221877888701411489680816282162734349635927251229227;
    UnitTestHelper testhelper;

    address[] public actors;

    address DAO = makeAddr("DAO");

    uint256[] guardiansEnclavePks;
    PufferProtocol pufferProtocol;
    IWETH weth;
    stETHMock stETH;

    EnumerableMap.AddressToUintMap _pufETHDepositors;
    EnumerableSet.AddressSet _nodeOperators;

    Permit emptyPermit;

    struct Data {
        address owner;
        bytes32 pubKeyPart;
    }

    // Mock signature for the validator deposit
    bytes mockValidatorSignature =
        hex"8aa088146c8c6ca6d8ad96648f20e791be7c449ce7035a6bd0a136b8c7b7867f730428af8d4a2b69658bfdade185d6110b938d7a59e98d905e922d53432e216dc88c3384157d74200d3f2de51d31737ce19098ff4d4f54f77f0175e23ac98da5";

    // Ghost variables for tracking
    uint256 public ghost_eth_deposited_amount;
    uint256 public ghost_weth;
    uint256 public ghost_steth;
    uint256 public ghost_locked_amount;
    uint256 public ghost_eth_rewards_amount;
    uint256 public ghost_block_number = 10000; // start blockNumber
    uint256 public ghost_validators = 0;
    uint256 public ghost_pufETH_bond_amount = 0; // bond amount that should be in puffer protocol
    ProvisionedValidator[] public ghost_validators_validating;

    address _accessManagerAdmin;

    // Previous ETH balance of the Vault
    uint256 public previousBalance;

    // This is important because that is the only way that ETH is leaving the Vault
    bool public ethLeavingThePool;

    // Helper state variable because of the stack too deep errors
    uint256 bondBurnAmount;

    // Counter for the calls in the invariant test
    mapping(bytes32 => uint256) public calls;
    uint256 totalCalls;

    struct ProvisioningData {
        Status status;
        bytes32 pubKeypart;
    }

    mapping(bytes32 queue => ProvisioningData[] validators) _validatorQueue;
    mapping(bytes32 queue => uint256 nextForProvisioning) ghost_nextForProvisioning;

    address internal currentActor;

    PufferVaultV2 pufferVault;
    PufferOracleV2 pufferOracle;
    ValidatorTicket validatorTicket;

    bool public printError;

    constructor(
        UnitTestHelper helper,
        PufferVaultV2 vault,
        address steth,
        PufferProtocol protocol,
        uint256[] memory _guardiansEnclavePks,
        address accessManagerAdmin
    ) {
        pufferVault = vault;
        pufferOracle = PufferOracleV2(address(protocol.PUFFER_ORACLE()));
        validatorTicket = protocol.VALIDATOR_TICKET();

        // Initialize actors, skip precompiles
        for (uint256 i = 11; i < 1000; ++i) {
            address actor = address(uint160(i));
            if (actor.code.length != 0) {
                continue;
            }
            vm.deal(actor, 1000 ether);

            actors.push(actor);
        }

        testhelper = helper;
        pufferProtocol = protocol;
        // This is after the upgrade to PufferVaultV2, when the WETH is the underlying asset
        weth = IWETH(vault.asset());
        stETH = stETHMock(steth);
        guardiansEnclavePks.push(_guardiansEnclavePks[0]);
        guardiansEnclavePks.push(_guardiansEnclavePks[1]);
        guardiansEnclavePks.push(_guardiansEnclavePks[2]);
        _accessManagerAdmin = accessManagerAdmin;
        _enableCall(pufferProtocol.getModuleAddress(bytes32("PUFFER_MODULE_0")));

        // Give initial liquidity to the PufferVault
        vm.deal(address(this), 20000 ether);

        // Initially ETH is the only assets in the vault
        ghost_eth_deposited_amount += pufferVault.totalAssets();
    }

    // Modifier to randomly select an actor
    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    // https://github.com/foundry-rs/foundry/issues/5795
    modifier setCorrectBlockNumber() {
        vm.roll(ghost_block_number);
        _;
    }

    // Records previous assets of the vault
    // Used in the invariant to check if the assets are leaving the pool
    modifier recordPreviousBalance() {
        previousBalance = pufferVault.totalAssets();
        _;
    }

    // Only on .withdraw the ETH is leaving the pool
    modifier isETHLeavingThePool() {
        if (msg.sig == this.withdraw.selector) {
            ethLeavingThePool = true;
        } else {
            ethLeavingThePool = false;
        }
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        totalCalls++;
        _;
    }

    // Buy validator tickets and pay for them in ETH
    // Anybody can purchase VT
    // VT Purchase rewards the pufETH holders
    function buyVT(uint256 depositorSeed, uint256 numberOfDays)
        public
        setCorrectBlockNumber
        recordPreviousBalance
        isETHLeavingThePool
        useActor(depositorSeed)
        countCall("buyVT")
    {
        // Random VT Amount between 1 and 200 VTS
        numberOfDays = bound(numberOfDays, 1, 200);
        uint256 amount = pufferOracle.getValidatorTicketPrice() * numberOfDays;

        // Do the math here as well to double check the amounts
        uint256 guardiansAmount = amount * validatorTicket.getGuardiansFeeRate() / (50 * 1 ether); // 0.5%
        uint256 treasuryAmount = amount * validatorTicket.getProtocolFeeRate() / (500 * 1 ether); // 5%
        uint256 vaultAmount = amount - (guardiansAmount + treasuryAmount);

        vm.deal(currentActor, amount);
        vm.expectEmit(true, true, true, true);
        emit IValidatorTicket.DispersedETH({ treasury: treasuryAmount, guardians: guardiansAmount, vault: vaultAmount });
        validatorTicket.purchaseValidatorTicket{ value: amount }(currentActor);
    }

    // User deposits ETH to get pufETH
    function depositETH(uint256 depositorSeed, uint256 amount)
        public
        useActor(depositorSeed)
        setCorrectBlockNumber
        recordPreviousBalance
        isETHLeavingThePool
        countCall("depositETH")
    {
        // bound the result between min deposit amount and uint64.max value ~18.44 ETH
        amount = bound(amount, 0.01 ether, uint256(type(uint64).max));
        vm.deal(currentActor, amount);

        uint256 expectedPufETHAmount = pufferVault.previewDeposit(amount);

        uint256 prevBalance = pufferVault.balanceOf(currentActor);

        uint256 pufETHAmount = pufferVault.depositETH{ value: amount }(currentActor);

        uint256 afterBalance = pufferVault.balanceOf(currentActor);

        ghost_eth_deposited_amount += amount;

        if (expectedPufETHAmount != (afterBalance - prevBalance)) {
            console.log("wrong calculation");
            printError = true;
        }

        if (pufETHAmount != expectedPufETHAmount) {
            console.log("amounts mismatch");
            printError = true;
        }

        // Store the depositor and amount of pufETH
        (, uint256 prevAmount) = _pufETHDepositors.tryGet(currentActor);
        _pufETHDepositors.set(currentActor, prevAmount + expectedPufETHAmount);
    }

    // User deposits stETH to get pufETH
    function depositStETH(uint256 depositorSeed, uint256 amount)
        public
        useActor(depositorSeed)
        setCorrectBlockNumber
        recordPreviousBalance
        isETHLeavingThePool
        countCall("depositStETH")
    {
        // bound the result between min deposit amount and uint64.max value ~18.44 ETH
        amount = bound(amount, 0.01 ether, uint256(type(uint64).max));
        stETH.mint(currentActor, amount);

        uint256 expectedPufETHAmount = pufferVault.previewDeposit(amount);

        uint256 prevBalance = pufferVault.balanceOf(currentActor);

        stETH.approve(address(pufferVault), amount);
        uint256 pufETHAmount = pufferVault.depositStETH(amount, currentActor);

        uint256 afterBalance = pufferVault.balanceOf(currentActor);

        ghost_steth += amount;

        if (expectedPufETHAmount != (afterBalance - prevBalance)) {
            console.log("wrong calculation");
            console.log("after balance:", (afterBalance - prevBalance));
            console.log("expected:", expectedPufETHAmount);
            // printError = true;
        }

        if (pufETHAmount != expectedPufETHAmount) {
            console.log("amounts mismatch");
            // printError = true;
        }

        // Store the depositor and amount of pufETH
        (, uint256 prevAmount) = _pufETHDepositors.tryGet(currentActor);
        _pufETHDepositors.set(currentActor, prevAmount + expectedPufETHAmount);
    }

    // Deposits WETH
    function depositWETH(uint256 depositorSeed, uint256 amount)
        public
        useActor(depositorSeed)
        setCorrectBlockNumber
        recordPreviousBalance
        isETHLeavingThePool
        countCall("depositWETH")
    {
        // bound the result between min deposit amount and uint64.max value ~18.44 ETH
        amount = bound(amount, 0.01 ether, uint256(type(uint64).max));
        stETHMock(address(weth)).mint(currentActor, amount);

        uint256 expectedPufETHAmount = pufferVault.previewDeposit(amount);

        uint256 prevBalance = pufferVault.balanceOf(currentActor);

        weth.approve(address(pufferVault), amount);
        uint256 pufETHAmount = pufferVault.deposit(amount, currentActor);

        uint256 afterBalance = pufferVault.balanceOf(currentActor);

        ghost_weth += amount;

        if (expectedPufETHAmount != (afterBalance - prevBalance)) {
            console.log("wrong calculation");
            printError = true;
        }

        if (pufETHAmount != expectedPufETHAmount) {
            console.log("amounts mismatch");
            printError = true;
        }

        // Store the depositor and amount of pufETH
        (, uint256 prevAmount) = _pufETHDepositors.tryGet(currentActor);
        _pufETHDepositors.set(currentActor, prevAmount + expectedPufETHAmount);
    }

    // withdraw pufETH for ETH
    function withdraw(uint256 withdrawerSeed)
        public
        setCorrectBlockNumber
        recordPreviousBalance
        isETHLeavingThePool
        countCall("withdraw")
    {
        // If there are no pufETH holders, deposit ETH
        if (_pufETHDepositors.length() == 0) {
            return;
        }

        uint256 withdrawerIndex = withdrawerSeed % _pufETHDepositors.length();

        (address withdrawer, uint256 amount) = _pufETHDepositors.at(withdrawerIndex);

        console.log("Withdrawer pufETH amount", amount);

        // Due to limited liquidity in WithdrawalPool, we are withdrawing 1/3 of the user's balance at a time
        uint256 burnAmount = amount / 3;
        _pufETHDepositors.set(withdrawer, (amount - burnAmount));

        console.log("PufferVault assets:", pufferVault.totalAssets());

        vm.startPrank(withdrawer);
        pufferVault.withdraw(burnAmount, withdrawer, withdrawer);

        vm.stopPrank();
    }

    // We have three of these to get better call distribution in the invariant tests
    function registerValidatorKey3(uint256 nodeOperatorSeed, bytes32 pubKeyPart, uint256 moduleSelectorSeed)
        public
        setCorrectBlockNumber
        useActor(nodeOperatorSeed)
        recordPreviousBalance
        isETHLeavingThePool
        countCall("registerValidatorKey")
    {
        _registerValidatorKey(pubKeyPart, moduleSelectorSeed);
    }

    function registerValidatorKey2(uint256 nodeOperatorSeed, bytes32 pubKeyPart, uint256 moduleSelectorSeed)
        public
        setCorrectBlockNumber
        useActor(nodeOperatorSeed)
        recordPreviousBalance
        isETHLeavingThePool
        countCall("registerValidatorKey")
    {
        _registerValidatorKey(pubKeyPart, moduleSelectorSeed);
    }

    // Registers Validator key
    function registerValidatorKey(uint256 nodeOperatorSeed, bytes32 pubKeyPart, uint256 moduleSelectorSeed)
        public
        setCorrectBlockNumber
        useActor(nodeOperatorSeed)
        recordPreviousBalance
        isETHLeavingThePool
        countCall("registerValidatorKey")
    {
        _registerValidatorKey(pubKeyPart, moduleSelectorSeed);
    }

    function _updateBlockNumber() internal {
        // advance block to where it can be updated next
        uint256 nextUpdate = block.number + 7149; // Update interval is 7141 `_UPDATE_INTERVAL` on pufferProtocol
        ghost_block_number = nextUpdate;
        vm.roll(nextUpdate);
    }

    function _registerValidatorKey(bytes32 pubKeyPart, uint256 moduleSelectorSeed) internal {
        bytes32[] memory moduleWeights = pufferProtocol.getModuleWeights();
        uint256 moduleIndex = moduleSelectorSeed % moduleWeights.length;

        bytes32 moduleName = moduleWeights[moduleIndex];

        pufferProtocol.getPendingValidatorIndex(moduleName);

        uint256 depositedETHAmount = _executeRegistration(pubKeyPart, moduleName);

        // Store data and push to queue
        ProvisioningData memory validator;
        validator.status = Status.PENDING;
        validator.pubKeypart = pubKeyPart;

        _validatorQueue[moduleName].push(validator);

        vm.stopPrank();

        // Account for that deposited eth in ghost variable
        ghost_eth_deposited_amount += depositedETHAmount;
        ghost_validators += 1;
        ghost_pufETH_bond_amount += pufferVault.previewDeposit(1 ether);

        // Add node operator to the set
        _nodeOperators.add(currentActor);
    }

    // Creates a puffer module and adds it to weights
    function createPufferModule(bytes32 moduleName)
        public
        setCorrectBlockNumber
        recordPreviousBalance
        isETHLeavingThePool
        countCall("createPufferModule")
    {
        vm.startPrank(DAO);

        bytes32[] memory weights = pufferProtocol.getModuleWeights();

        bytes32[] memory newWeights = new bytes32[](weights.length + 1);
        for (uint256 i = 0; i < weights.length; ++i) {
            newWeights[i] = weights[i];
        }

        try pufferProtocol.createPufferModule(moduleName) {
            newWeights[weights.length] = moduleName;
            pufferProtocol.setModuleWeights(newWeights);
            address createdModule = pufferProtocol.getModuleAddress(moduleName);
            _enableCall(createdModule);
        } catch { }

        vm.stopPrank();
    }

    // Starts the validating process
    function provisionNode()
        public
        setCorrectBlockNumber
        recordPreviousBalance
        isETHLeavingThePool
        countCall("provisionNode")
    {
        // If we don't have proxies, create and register validator key, then call this function again with the same params
        if (_nodeOperators.length() == 0) {
            ethLeavingThePool = false;
            return;
        }

        // If there is nothing to be provisioned, index returned is max uint256
        (, uint256 i) = pufferProtocol.getNextValidatorToProvision();
        if (i == type(uint256).max) {
            ethLeavingThePool = false;
            return;
        }

        uint256 moduleSelectIndex = pufferProtocol.getModuleSelectIndex();
        bytes32[] memory weights = pufferProtocol.getModuleWeights();

        bytes32 moduleName = weights[moduleSelectIndex % weights.length];

        uint256 nextIdx = ghost_nextForProvisioning[moduleName];

        // Nothing to provision
        if (_validatorQueue[moduleName].length <= nextIdx) {
            ethLeavingThePool = false;
            return;
        }

        ProvisioningData memory validatorData = _validatorQueue[moduleName][nextIdx];

        if (validatorData.status == Status.PENDING) {
            bytes memory sig = _getPubKey(validatorData.pubKeypart);

            bytes[] memory signatures = _getGuardianSignatures(sig);
            pufferProtocol.provisionNode(signatures, mockValidatorSignature, bytes32(0));

            ghost_validators_validating.push(ProvisionedValidator({ moduleName: moduleName, idx: nextIdx }));

            // Update ghost variables
            ghost_locked_amount += 32 ether;
            ghost_nextForProvisioning[moduleName]++;
        }
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("totalCalls", totalCalls);
        console.log("buyVT", calls["buyVT"]);
        console.log("depositETH", calls["depositETH"]);
        console.log("depositWETH", calls["depositWETH"]);
        console.log("withdraw", calls["withdraw"]);
        console.log("registerValidatorKey", calls["registerValidatorKey"]);
        console.log("createPufferModule", calls["createPufferModule"]);
        console.log("provisionNode", calls["provisionNode"]);
        console.log("postFullWithdrawalsProof", calls["postFullWithdrawalsProof"]);
        console.log("-------------------");
    }

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

        ValidatorKeyData memory validatorData = ValidatorKeyData({
            blsPubKey: pubKey, // key length must be 48 byte
            // mock signature copied from some random deposit transaction
            signature: mockValidatorSignature,
            depositDataRoot: pufferProtocol.getDepositDataRoot({
                pubKey: pubKey,
                signature: mockValidatorSignature,
                withdrawalCredentials: withdrawalCredentials
            }),
            blsEncryptedPrivKeyShares: new bytes[](3),
            blsPubKeySet: new bytes(48),
            raveEvidence: new bytes(1) // Guardians are checking it off chain
         });

        return validatorData;
    }

    function _getPubKey(bytes32 pubKeypart) internal pure returns (bytes memory) {
        return bytes.concat(abi.encodePacked(pubKeypart), bytes16(""));
    }

    /**
     * @dev Registers a validator key for a random number of days between 30 and 300
     * Assumes all validators use ENCLAVE and have 1 ETH bond
     */
    function _executeRegistration(bytes32 pubKeyPart, bytes32 moduleName)
        internal
        returns (uint256 depositedETHAmount)
    {
        // Fund the node operator
        vm.deal(currentActor, 50 ether);

        uint256 numberOfDays = bound(block.timestamp, 30, 300);
        uint256 smoothingCommitment = numberOfDays * pufferProtocol.PUFFER_ORACLE().getValidatorTicketPrice();

        bytes memory pubKey = _getPubKey(pubKeyPart);

        ValidatorKeyData memory validatorKeyData = _getMockValidatorKeyData(pubKey, moduleName);

        uint256 idx = pufferProtocol.getPendingValidatorIndex(moduleName);

        uint256 bond = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit IPufferProtocol.ValidatorKeyRegistered(pubKey, idx, moduleName, true);
        pufferProtocol.registerValidatorKey{ value: (smoothingCommitment + bond) }(
            validatorKeyData, moduleName, emptyPermit, emptyPermit
        );

        return (smoothingCommitment + bond);
    }

    // Copied from PufferProtocol.t.sol
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
            mockValidatorSignature,
            withdrawalCredentials,
            pufferProtocol.getDepositDataRoot({
                pubKey: pubKey,
                signature: mockValidatorSignature,
                withdrawalCredentials: withdrawalCredentials
            })
        );

        return _getGuardianEnclaveSignatures(digest);
    }

    function _getGuardianEnclaveSignatures(bytes32 digest) internal view returns (bytes[] memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guardian1SKEnclave, digest);
        bytes memory signature1 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian2SKEnclave, digest);
        bytes memory signature2 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        (v, r, s) = vm.sign(guardian3SKEnclave, digest);
        bytes memory signature3 = abi.encodePacked(r, s, v); // note the order here is different from line above.

        bytes[] memory guardianSignatures = new bytes[](3);
        guardianSignatures[0] = signature1;
        guardianSignatures[1] = signature2;
        guardianSignatures[2] = signature3;

        return guardianSignatures;
    }

    function _getGuardianEOASignatures(bytes32 digest) internal returns (bytes[] memory) {
        // Create Guardian wallets
        (, uint256 guardian1SK) = makeAddrAndKey("guardian1");
        (, uint256 guardian2SK) = makeAddrAndKey("guardian2");
        (, uint256 guardian3SK) = makeAddrAndKey("guardian3");
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

    function _buildMerkle(
        ProvisionedValidator memory first,
        uint256 firstAmount,
        ProvisionedValidator memory second,
        uint256 secondAmount,
        bool slashed
    ) public returns (bytes32, bytes32[] memory, bytes32[] memory) {
        // Initialize
        Merkle m = new Merkle();
        uint256 wasSlashed = slashed == true ? 1 : 0;

        // see PufferProtocol.retrieveBond() on how the merkle proof is created
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(
            bytes.concat(keccak256(abi.encode(first.moduleName, first.idx, firstAmount, block.timestamp, uint8(0))))
        );
        data[1] = keccak256(
            bytes.concat(
                keccak256(abi.encode(second.moduleName, second.idx, secondAmount, block.timestamp, uint8(wasSlashed)))
            )
        );

        // Get Root, Proof, and Verify
        bytes32 root = m.getRoot(data);
        bytes32[] memory proof1 = m.getProof(data, 0);
        bytes32[] memory proof2 = m.getProof(data, 1);

        return (root, proof1, proof2);
    }

    function _enableCall(address module) internal {
        // Enable PufferProtocol to call `call` function on module
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IPufferModule.call.selector;
        vm.startPrank(_accessManagerAdmin);
        AccessManager(pufferProtocol.authority()).setTargetFunctionRole(module, selectors, ROLE_ID_PUFFER_PROTOCOL);
        vm.stopPrank();
    }
}
