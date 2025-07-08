// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { EpochsValidatedSignature } from "../struct/Signatures.sol";

interface IPufferProtocolLogic {
    function _requestConsolidation(bytes32 moduleName, uint256[] calldata srcIndices, uint256[] calldata targetIndices)
        external
        payable;

    /**
     * @dev Internal function to return the deprecated validator tickets burn amount
     *      and/or consume the validation time from the node operator
     * @dev The deprecated vt balance is reduced here but the actual VT is not burned here (for efficiency)
     * @param epochsValidatedSignature is a struct that contains:
     * - functionSelector: Identifier of the function that initiated this flow
     * - totalEpochsValidated: The total number of epochs validated by that node operator
     * - nodeOperator: The node operator address
     * - deadline: The deadline for the signature
     * - signatures: The signatures of the guardians over the total number of epochs validated
     * @return vtAmountToBurn The amount of VT to burn
     */
    function _useVTOrValidationTime(EpochsValidatedSignature memory epochsValidatedSignature)
        external
        payable
        returns (uint256 vtAmountToBurn);

    /**
     * @dev Internal function to settle the VT accounting for a node operator
     * @param epochsValidatedSignature is a struct that contains:
     * - functionSelector: Identifier of the function that initiated this flow
     * - totalEpochsValidated: The total number of epochs validated by that node operator
     * - nodeOperator: The node operator address
     * - deadline: The deadline for the signature
     * - signatures: The signatures of the guardians over the total number of epochs validated
     * @param deprecated_burntVTs The amount of VT to burn (to be deducted from validation time consumption)
     */
    function _settleVTAccounting(EpochsValidatedSignature memory epochsValidatedSignature, uint256 deprecated_burntVTs)
        external
        payable;
}
