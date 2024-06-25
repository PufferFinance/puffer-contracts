// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Permit } from "../../mainnet-contracts/src/structs/Permit.sol";
import { ValidatorKeyData } from "mainnet-contracts/src/struct/ValidatorKeyData.sol";
import { IPufferProtocol } from "mainnet-contracts/src/interface/IPufferProtocol.sol";
import { PufferProtocol } from "mainnet-contracts/src/PufferProtocol.sol";
import { PufferVaultV2 } from "mainnet-contracts/src/PufferVaultV2.sol";
import { ValidatorTicket } from "mainnet-contracts/src/ValidatorTicket.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * See the docs for more detailed information: https://docs.puffer.fi/nodes/registration#batch-registering-validators
 *
 *  To run the simulation:
 *
 * forge script script/GenerateBLSKeysAndRegisterValidatorsCalldata.s.sol:GenerateBLSKeysAndRegisterValidatorsCalldata --rpc-url=$RPC_URL -vvv --ffi
 *
 */
contract GenerateBLSKeysAndRegisterValidatorsCalldata is Script {
    address validatorTicketAddress;
    PufferVaultV2 internal pufETH;
    ValidatorTicket internal validatorTicket;
    address internal protocolAddress;
    PufferProtocol internal pufferProtocol;
    string internal registrationJson;

    string forkVersion;

    bytes32 moduleToRegisterTo;

    mapping(bytes32 keyHash => bool registered) internal pubKeys;
    bytes[] internal registeredPubKeys;

    struct Tx {
        address to;
        bytes data;
    }

    function setUp() public {
        if (block.chainid == 17000) {
            // Holesky
            validatorTicketAddress = 0xB028194785178a94Fe608994A4d5AD84c285A640;
            protocolAddress = 0xE00c79408B9De5BaD2FDEbB1688997a68eC988CD;
            pufferProtocol = PufferProtocol(protocolAddress);
            forkVersion = "0x01017000";
        } else if (block.chainid == 1) {
            // Mainnet
            validatorTicketAddress = 0x7D26AD6F6BA9D6bA1de0218Ae5e20CD3a273a55A;
            protocolAddress = 0xf7b6B32492c2e13799D921E84202450131bd238B;
            pufferProtocol = PufferProtocol(protocolAddress);
            forkVersion = "0x00000000";
        }

        pufETH = pufferProtocol.PUFFER_VAULT();
        validatorTicket = pufferProtocol.VALIDATOR_TICKET();
    }

    function run() public {
        uint256 guardiansLength = pufferProtocol.GUARDIAN_MODULE().getGuardians().length;

        uint256 specificModule = vm.promptUint("Do you want to register to a specific module? (0: No, 1: Yes)");
        if (specificModule == 1) {
            uint256 pufferModuleIdx = vm.promptUint(
                "Please enter the module number to which you wish to register. Enter '0' to register to PUFFER_MODULE_0, Enter '1' to register to PUFFER_MODULE_1, ..."
            );
            moduleToRegisterTo =
                bytes32(abi.encodePacked(string.concat("PUFFER_MODULE_", vm.toString(pufferModuleIdx))));
        }

        uint256 numberOfValidators = vm.promptUint("How many validators would you like to register?");
        require(numberOfValidators > 0, "Number of validators must be greater than 0");

        uint256 vtAmount = vm.promptUint("Enter the VT amount per validator (28 is minimum)");
        require(vtAmount >= 28, "VT amount must be at least 28");

        address safe = vm.promptAddress("Enter the safe address");
        require(safe != address(0), "Invalid safe address");

        // Validate pufETH & VT balances
        _validateBalances(safe, numberOfValidators, vtAmount);

        bytes32[] memory moduleWeights = pufferProtocol.getModuleWeights();
        uint256 moduleSelectionIndex = pufferProtocol.getModuleSelectIndex();

        bytes memory approveVTCalldata =
            abi.encodeCall(ERC20.approve, (protocolAddress, vtAmount * numberOfValidators * 1 ether));
        bytes memory approvePufETHCalldata =
            abi.encodeCall(ERC20.approve, (protocolAddress, 2 ether * numberOfValidators));

        // 2 token approvals + validator registrations
        Tx[] memory transactions = new Tx[](numberOfValidators + 2);
        transactions[0] = Tx({ to: validatorTicketAddress, data: approveVTCalldata });
        transactions[1] = Tx({ to: address(pufETH), data: approvePufETHCalldata });

        for (uint256 i = 0; i < numberOfValidators; ++i) {
            // Select the module to register to
            bytes32 moduleName = moduleWeights[(moduleSelectionIndex + i) % moduleWeights.length];

            // If the user specified a module to register to, use that instead
            if (moduleToRegisterTo != bytes32(0)) {
                require(pufferProtocol.getModuleAddress(moduleToRegisterTo) != address(0), "Invalid Puffer Module");
                moduleName = moduleToRegisterTo;
            }

            _generateValidatorKey(i, moduleName);

            // Read the registration JSON file
            registrationJson = vm.readFile(string.concat("./registration-data/", vm.toString(i), ".json"));

            bytes[] memory blsEncryptedPrivKeyShares = new bytes[](guardiansLength);
            blsEncryptedPrivKeyShares[0] = stdJson.readBytes(registrationJson, ".bls_enc_priv_key_shares[0]");

            ValidatorKeyData memory validatorData = ValidatorKeyData({
                blsPubKey: stdJson.readBytes(registrationJson, ".bls_pub_key"),
                signature: stdJson.readBytes(registrationJson, ".signature"),
                depositDataRoot: stdJson.readBytes32(registrationJson, ".deposit_data_root"),
                blsEncryptedPrivKeyShares: blsEncryptedPrivKeyShares,
                blsPubKeySet: stdJson.readBytes(registrationJson, ".bls_pub_key_set"),
                raveEvidence: ""
            });

            Permit memory pufETHPermit;
            pufETHPermit.amount = 2 ether;

            Permit memory vtPermit;
            vtPermit.amount = vtAmount * 1 ether;

            bytes memory registerValidatorKeyCalldata =
                abi.encodeCall(PufferProtocol.registerValidatorKey, (validatorData, moduleName, pufETHPermit, vtPermit));

            transactions[i + 2] = Tx({ to: protocolAddress, data: registerValidatorKeyCalldata });

            registeredPubKeys.push(validatorData.blsPubKey);
        }

        // Create Safe TX JSON
        _createSafeJson(safe, transactions);

        console.log("Validator PubKeys:");
        for (uint256 i = 0; i < registeredPubKeys.length; ++i) {
            console.logBytes(registeredPubKeys[i]);
        }
    }

    function _createSafeJson(address safe, Tx[] memory transactions) internal {
        // First we need to craft the JSON file for the transactions batch
        string memory root = "root";

        vm.serializeString(root, "version", "\"1.0\"");
        vm.serializeUint(root, "createdAt", block.timestamp * 1000);
        // Needs to be a string
        vm.serializeString(root, "chainId", string.concat("\"", Strings.toString(block.chainid), "\""));

        string memory meta = "meta";
        vm.serializeString(meta, "name", "Transactions Batch");
        vm.serializeString(meta, "txBuilderVersion", "\"1.16.5\"");
        vm.serializeAddress(meta, "createdFromSafeAddress", safe);
        vm.serializeString(meta, "createdFromOwnerAddress", "");
        vm.serializeString(meta, "checksum", "");
        string memory metaOutput = vm.serializeString(meta, "description", "");

        string[] memory txs = new string[](transactions.length);

        for (uint256 i = 0; i < transactions.length; ++i) {
            string memory singleTx = "tx";

            vm.serializeAddress(singleTx, "to", transactions[i].to);
            vm.serializeString(singleTx, "value", "\"0\"");
            txs[i] = vm.serializeBytes(singleTx, "data", transactions[i].data);
        }

        vm.serializeString(root, "transactions", txs);
        string memory finalJson = vm.serializeString(root, "meta", metaOutput);
        vm.writeJson(finalJson, "./safe-registration-file.json");

        // Because foundry doesn't support creating JSON array of objects, we need to run NodeJS script to convert this to a valid JSON

        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "parse-foundry-json";
        vm.ffi(inputs);
    }

    // Validates the pufETH and VT balances for the `safe` (node operator)
    function _validateBalances(address safe, uint256 numberOfValidators, uint256 vtBalancePerValidator) internal view {
        uint256 pufETHRequired = pufETH.convertToSharesUp(numberOfValidators * 2 ether);

        if (pufETH.balanceOf(safe) < pufETHRequired) {
            revert("Insufficient pufETH balance");
        }

        uint256 vtRequired = numberOfValidators * vtBalancePerValidator * 1 ether;

        if (validatorTicket.balanceOf(safe) < vtRequired) {
            revert("Insufficient VT balance");
        }
    }

    // Generates a new validator key using coral https://github.com/PufferFinance/coral/tree/main
    function _generateValidatorKey(uint256 idx, bytes32 moduleName) internal {
        uint256 numberOfGuardians = pufferProtocol.GUARDIAN_MODULE().getGuardians().length;
        bytes[] memory guardianPubKeys = pufferProtocol.GUARDIAN_MODULE().getGuardiansEnclavePubkeys();
        address moduleAddress = IPufferProtocol(protocolAddress).getModuleAddress(moduleName);
        bytes memory withdrawalCredentials = IPufferProtocol(protocolAddress).getWithdrawalCredentials(moduleAddress);

        string[] memory inputs = new string[](17);
        inputs[0] = "coral-cli";
        inputs[1] = "validator";
        inputs[2] = "keygen";
        inputs[3] = "--guardian-threshold";
        inputs[4] = vm.toString(numberOfGuardians);
        inputs[5] = "--module-name";
        inputs[6] = vm.toString(moduleName);
        inputs[7] = "--withdrawal-credentials";
        inputs[8] = vm.toString(withdrawalCredentials);
        inputs[9] = "--guardian-pubkeys";
        inputs[10] = vm.toString(guardianPubKeys[0]); //@todo: Add support for multiple guardians
        inputs[11] = "--fork-version";
        inputs[12] = forkVersion;
        inputs[13] = "--password-file";
        inputs[14] = "validator-keystore-password.txt";
        inputs[15] = "--output-file";
        inputs[16] = string.concat("./registration-data/", vm.toString(idx), ".json");

        vm.ffi(inputs);
    }
}
