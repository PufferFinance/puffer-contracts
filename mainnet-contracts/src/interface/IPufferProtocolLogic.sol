// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { EpochsValidatedSignature } from "../struct/Signatures.sol";
import { StoppedValidatorInfo } from "../struct/StoppedValidatorInfo.sol";
import { ValidatorKeyData } from "../struct/ValidatorKeyData.sol";

interface IPufferProtocolLogic {
    /**
     * @notice Check IPufferProtocol.depositValidationTime
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function _depositValidationTime(EpochsValidatedSignature memory epochsValidatedSignature) external payable;

    /**
     * @notice Check IPufferProtocol.withdrawValidationTime
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function _withdrawValidationTime(uint96 amount, address recipient) external;

    /**
     * @notice Check IPufferProtocol.registerValidatorKey
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function _registerValidatorKey(
        ValidatorKeyData calldata data,
        bytes32 moduleName,
        uint256 totalEpochsValidated,
        bytes[] calldata vtConsumptionSignature,
        uint256 deadline
    ) external payable;

    /**
     * @notice Check IPufferProtocol.requestConsolidation
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function _requestConsolidation(bytes32 moduleName, uint256[] calldata srcIndices, uint256[] calldata targetIndices)
        external
        payable;

    /**
     * @notice Check IPufferProtocol.skipProvisioning
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function _skipProvisioning(bytes32 moduleName, bytes[] calldata guardianEOASignatures) external;

    /**
     * @notice Check IPufferProtocol.batchHandleWithdrawals
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function _batchHandleWithdrawals(
        StoppedValidatorInfo[] calldata validatorInfos,
        bytes[] calldata guardianEOASignatures,
        uint256 deadline
    ) external payable;
}
