// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Permit } from "../src/structs/Permit.sol";
import { ValidatorKeyData } from "../src/struct/ValidatorKeyData.sol";
import { IPufferProtocol } from "../src/interface/IPufferProtocol.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { PufferVaultV2 } from "../src/PufferVaultV2.sol";
import { ValidatorTicket } from "../src/ValidatorTicket.sol";

/**
 *  Replace the `--sender=0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0` with the address that will be used to sign the permits matches the keystore used by --account
 * See the docs for more detailed information: https://docs.puffer.fi/nodes/registration#batch-registering-validators
 *
 *  To run the simulation:
 *
 * forge script script/GenerateBLSKeysAndRegisterValidators.s.sol:GenerateBLSKeysAndRegisterValidators --rpc-url=$RPC_URL --account $KEYSTORE_NAME -vvv --sender=$KEYSTORE_ADDRESS --ffi
 *
 *  To broadcast the transaction on-chain, add `--broadcast --slow` flag at the end of the command
 */
contract GenerateBLSKeysAndRegisterValidators is Script {
    PufferVaultV2 internal pufETH;
    ValidatorTicket internal validatorTicket;
    address internal protocolAddress;
    PufferProtocol internal pufferProtocol;
    string internal registrationJson;

    string forkVersion;

    bytes32 moduleToRegisterTo;

    mapping(bytes32 keyHash => bool registered) internal pubKeys;
    bytes[] internal registeredPubKeys;

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        if (block.chainid == 17000) {
            // Holesky
            protocolAddress = 0xE00c79408B9De5BaD2FDEbB1688997a68eC988CD;
            pufferProtocol = PufferProtocol(protocolAddress);
            forkVersion = "0x01017000";
        } else if (block.chainid == 1) {
            // Mainnet
            protocolAddress = 0xf7b6B32492c2e13799D921E84202450131bd238B;
            pufferProtocol = PufferProtocol(protocolAddress);
            forkVersion = "0x00000000";
        }

        pufETH = pufferProtocol.PUFFER_VAULT();
        validatorTicket = pufferProtocol.VALIDATOR_TICKET();
    }

    function run() public {
        vm.startBroadcast();

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

        // Validate pufETH & VT balances
        _validateBalances(numberOfValidators, vtAmount);

        bytes32[] memory moduleWeights = pufferProtocol.getModuleWeights();
        uint256 moduleSelectionIndex = pufferProtocol.getModuleSelectIndex();

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

            Permit memory pufETHPermit = _signPermit({
                to: protocolAddress,
                amount: 2 ether, // Hardcoded to 2 pufETH
                nonce: pufETH.nonces(msg.sender),
                deadline: block.timestamp + 12 hours,
                domainSeparator: pufETH.DOMAIN_SEPARATOR()
            });

            Permit memory vtPermit = _signPermit({
                to: protocolAddress,
                amount: vtAmount * 1 ether, // Upscale to 10**18
                nonce: validatorTicket.nonces(msg.sender),
                deadline: block.timestamp + 12 hours,
                domainSeparator: validatorTicket.DOMAIN_SEPARATOR()
            });

            IPufferProtocol(protocolAddress).registerValidatorKey(validatorData, moduleName, pufETHPermit, vtPermit);

            registeredPubKeys.push(validatorData.blsPubKey);
        }

        console.log("Registered PubKeys:");
        console.log(
            "------------------------------------------------------------------------------------------------------------------------"
        );
        for (uint256 i = 0; i < registeredPubKeys.length; ++i) {
            console.logBytes(registeredPubKeys[i]);
        }
    }

    // Validates the pufETH and VT balances for the msg.sender (node operator)
    function _validateBalances(uint256 numberOfValidators, uint256 vtBalancePerValidator) internal view {
        uint256 pufETHRequired = pufETH.convertToSharesUp(numberOfValidators * 2 ether);

        if (pufETH.balanceOf(msg.sender) < pufETHRequired) {
            revert("Insufficient pufETH balance");
        }

        uint256 vtRequired = numberOfValidators * vtBalancePerValidator * 1 ether;

        if (validatorTicket.balanceOf(msg.sender) < vtRequired) {
            revert("Insufficient VT balance");
        }
    }

    // Signs the Permit for VT & puETH
    function _signPermit(address to, uint256 amount, uint256 nonce, uint256 deadline, bytes32 domainSeparator)
        internal
        view
        returns (Permit memory p)
    {
        address operator = msg.sender;
        bytes32 innerHash = keccak256(abi.encode(_PERMIT_TYPEHASH, operator, to, amount, nonce, deadline));
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(outerHash);

        return Permit({ deadline: deadline, amount: amount, v: v, r: r, s: s });
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
