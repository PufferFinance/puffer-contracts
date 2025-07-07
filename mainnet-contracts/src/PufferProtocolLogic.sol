// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferProtocolStorage } from "./PufferProtocolStorage.sol";
import { ProtocolStorage } from "./struct/ProtocolStorage.sol";
import { ProtocolSignatureNonces } from "./ProtocolSignatureNonces.sol";
import { Validator } from "./struct/Validator.sol";
import { Status } from "./struct/Validator.sol";
import { ProtocolConstants } from "./ProtocolConstants.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";

contract PufferProtocolLogic is PufferProtocolStorage, ProtocolSignatureNonces, ProtocolConstants {
    /**
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function _requestConsolidation(bytes32 moduleName, uint256[] calldata srcIndices, uint256[] calldata targetIndices)
        external
        payable
    {
        if (srcIndices.length == 0) {
            revert InputArrayLengthZero();
        }
        if (srcIndices.length != targetIndices.length) {
            revert InputArrayLengthMismatch();
        }

        ProtocolStorage storage $ = _getPufferProtocolStorage();

        bytes[] memory srcPubkeys = new bytes[](srcIndices.length);
        bytes[] memory targetPubkeys = new bytes[](targetIndices.length);
        Validator storage validatorSrc;
        Validator storage validatorTarget;
        for (uint256 i = 0; i < srcPubkeys.length; i++) {
            require(srcIndices[i] != targetIndices[i], InvalidValidator());
            validatorSrc = $.validators[moduleName][srcIndices[i]];
            require(validatorSrc.node == msg.sender && validatorSrc.status == Status.ACTIVE, InvalidValidator());
            srcPubkeys[i] = validatorSrc.pubKey;
            validatorTarget = $.validators[moduleName][targetIndices[i]];
            require(validatorTarget.node == msg.sender && validatorTarget.status == Status.ACTIVE, InvalidValidator());
            targetPubkeys[i] = validatorTarget.pubKey;

            // Update accounting
            validatorTarget.bond += validatorSrc.bond;
            validatorTarget.numBatches += validatorSrc.numBatches;

            delete $.validators[moduleName][srcIndices[i]];
            // Node info needs no update since all stays in the same node operator
        }

        $.modules[moduleName].requestConsolidation{ value: msg.value }(srcPubkeys, targetPubkeys);

        emit IPufferProtocol.ConsolidationRequested(moduleName, srcPubkeys, targetPubkeys);
    }
}
