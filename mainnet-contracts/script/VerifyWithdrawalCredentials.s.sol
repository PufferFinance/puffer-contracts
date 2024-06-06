// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { Validator } from "../src/struct/Validator.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ProofParsing } from "../test/helpers/ProofParsing.sol";
import { BeaconChainProofs } from "eigenlayer/libraries/BeaconChainProofs.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";

/**
 * @dev Example on how to run the script
 *
 *      Holesky Example of a withdrawal credentials verification
 *      https://holesky.etherscan.io/tx/0xf7332d953741ad616e1a72b27545b2e66c56224a1fe145e0d65ea4512f0c3a12#eventlog
 *
 *      forge script script/VerifyWithdrawalCredentials.s.sol:VerifyWithdrawalCredentials --rpc-url=$RPC_URL --sig "run(address,uint64,uint40[],bytes32)" "0xe4695ab93163F91665Ce5b96527408336f070a71" "1713162504" "[1663110,1663111,1663113,1663125,1663128]" "0x5055464645525f4d4f44554c455f300000000000000000000000000000000000" --broadcast --private-key=$PK
 */
contract VerifyWithdrawalCredentials is Script, ProofParsing {
    function run(
        address pufferModuleManager,
        uint64 oracleTimestamp,
        uint40[] calldata validatorIndices,
        bytes32 moduleName
    ) external {
        // Use the first file to get the state root proof
        string memory filePath = string.concat("./proofs/", vm.toString(validatorIndices[0]), ".json");
        setJSON(filePath);
        BeaconChainProofs.StateRootProof memory stateRootProofStruct = _getStateRootProof();

        bytes32[][] memory validatorFields = new bytes32[][](validatorIndices.length);
        bytes[] memory validatorFieldsProofs = new bytes[](validatorIndices.length);

        // Get validator fields and proofs
        for (uint256 i = 0; i < validatorIndices.length; ++i) {
            filePath = string.concat("./proofs/", vm.toString(validatorIndices[i]), ".json");
            // console.log("Reading proof from file: ", filePath);
            setJSON(filePath);

            // Get the validator fields
            validatorFields[i] = getValidatorFields();
            validatorFieldsProofs[i] = abi.encodePacked(getWithdrawalCredentialProof());
        }

        // Craft the calldata
        bytes memory moduleManagerCallData = abi.encodeCall(
            PufferModuleManager.callVerifyWithdrawalCredentials,
            (
                moduleName,
                oracleTimestamp,
                stateRootProofStruct,
                validatorIndices,
                validatorFieldsProofs,
                validatorFields
            )
        );

        vm.startBroadcast();
        (bool s, bytes memory response) = address(pufferModuleManager).call(moduleManagerCallData);
        console.logBytes(response);
        require(s, "Call failed");
    }

    function _getStateRootProof() internal returns (BeaconChainProofs.StateRootProof memory) {
        return BeaconChainProofs.StateRootProof(getBeaconStateRoot(), abi.encodePacked(getStateRootProof()));
    }
}
