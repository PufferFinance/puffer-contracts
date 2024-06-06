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
 *      Holesky Example of a queue withdrawals
 *      https://holesky.etherscan.io/tx/0x9ccbefc8d5606d8d74c4cde3503416107bcf36c4194fef5d2321ce48f316be1f#eventlog
 *
 *      forge script script/VerifyAndProcessWithdrawals.s.sol:VerifyAndProcessWithdrawals --rpc-url=$RPC_URL --sig "run(address,uint64,uint40[],bytes32)" "0xe4695ab93163F91665Ce5b96527408336f070a71" "1713500196" "[1632140]" "0x5055464645525f4d4f44554c455f300000000000000000000000000000000000" --broadcast --private-key=$PK
 */
contract VerifyAndProcessWithdrawals is Script, ProofParsing {
    function run(
        address pufferModuleManager,
        uint64 oracleTimestamp,
        uint40[] calldata validatorIndices,
        bytes32 moduleName
    ) external {
        // Use the first file to get the state root proof
        string memory filePath = string.concat("./proofs/", vm.toString(validatorIndices[0]), "-withdrawal.json");
        setJSON(filePath);

        BeaconChainProofs.StateRootProof memory stateRootProof = _getStateRootProof();
        bytes32[][] memory validatorFields = new bytes32[][](validatorIndices.length);
        bytes32[][] memory withdrawalFields = new bytes32[][](validatorIndices.length);
        bytes[] memory validatorFieldsProofs = new bytes[](validatorIndices.length);
        BeaconChainProofs.WithdrawalProof[] memory withdrawalProofs =
            new BeaconChainProofs.WithdrawalProof[](validatorIndices.length);

        // Get validator fields and proofs
        for (uint256 i = 0; i < validatorIndices.length; ++i) {
            filePath = string.concat("./proofs/", vm.toString(validatorIndices[i]), "-withdrawal.json");
            // console.log("Reading proof from file: ", filePath);
            setJSON(filePath);

            // Get the validator fields
            validatorFields[i] = getValidatorFields();
            validatorFieldsProofs[i] = abi.encodePacked(getValidatorProof());
            withdrawalFields[i] = getWithdrawalFields();
            withdrawalProofs[i] = _getWithdrawalProof();
        }

        // Craft the calldata
        bytes memory moduleManagerCallData = abi.encodeCall(
            PufferModuleManager.callVerifyAndProcessWithdrawals,
            (
                moduleName,
                oracleTimestamp,
                stateRootProof,
                withdrawalProofs,
                validatorFieldsProofs,
                validatorFields,
                withdrawalFields
            )
        );

        vm.startBroadcast();
        (bool s, bytes memory response) = address(pufferModuleManager).call(moduleManagerCallData);
        console.logBytes(response);
        require(s, "Call failed");
    }

    function _getWithdrawalProof() internal returns (BeaconChainProofs.WithdrawalProof memory) {
        return BeaconChainProofs.WithdrawalProof(
            abi.encodePacked(getWithdrawalProofDeneb()),
            abi.encodePacked(getSlotProof()),
            abi.encodePacked(getExecutionPayloadProof()),
            abi.encodePacked(getTimestampProofDeneb()),
            abi.encodePacked(getHistoricalSummaryProof()),
            uint64(getBlockRootIndex()),
            uint64(getHistoricalSummaryIndex()),
            uint64(getWithdrawalIndex()),
            getBlockRoot(),
            getSlotRoot(),
            getTimestampRoot(),
            getExecutionPayloadRoot()
        );
    }

    function _getStateRootProof() internal returns (BeaconChainProofs.StateRootProof memory) {
        return BeaconChainProofs.StateRootProof(getBeaconStateRoot(), abi.encodePacked(getStateRootProof()));
    }
}
