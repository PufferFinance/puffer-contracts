// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { EpochsValidatedSignature } from "../struct/Signatures.sol";
import { StoppedValidatorInfo } from "../struct/StoppedValidatorInfo.sol";
import { ValidatorKeyData } from "../struct/ValidatorKeyData.sol";

interface IPufferProtocolLogic {
    /**
     * @notice New function that allows anybody to deposit ETH for a node operator (use this instead of `depositValidatorTickets`).
     * Deposits Validation Time for the `node`. Validation Time is in native ETH.
     * @param epochsValidatedSignature is a struct that contains:
     * - functionSelector: Can be left empty, it will be used to prevent replay attacks
     * - totalEpochsValidated: The total number of epochs validated by that node operator
     * - nodeOperator: The node operator address
     * - deadline: The deadline for the signature
     * - signatures: The signatures of the guardians over the total number of epochs validated
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function depositValidationTime(EpochsValidatedSignature memory epochsValidatedSignature) external payable;

    /**
     * @notice New function that allows the transaction sender (node operator) to withdraw WETH to a recipient (use this instead of `withdrawValidatorTickets`)
     * The Validation time can be withdrawn if there are no active or pending validators
     * The WETH is sent to the recipient
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function withdrawValidationTime(uint96 amount, address recipient) external;

    /**
     * @notice Registers a validator key and consumes the ETH for the validation time for the other active validators.
     * @dev There is a queue per moduleName and it is FIFO
     * @param data The validator key data
     * @param moduleName The name of the module
     * @param totalEpochsValidated The total number of epochs validated by the validator
     * @param vtConsumptionSignature The signature of the guardians to validate the number of epochs validated
     * @param deadline The deadline for the signature
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function registerValidatorKey(
        ValidatorKeyData calldata data,
        bytes32 moduleName,
        uint256 totalEpochsValidated,
        bytes[] calldata vtConsumptionSignature,
        uint256 deadline
    ) external payable;

    /**
     * @notice Requests a consolidation for the given validators. This consolidation consists on merging one validator into another one
     * @param moduleName The name of the module
     * @param srcIndices The indices of the validators to consolidate from
     * @param targetIndices The indices of the validators to consolidate to
     * @dev According to EIP-7251 there is a fee for each validator consolidation request (See https://eips.ethereum.org/EIPS/eip-7251#fee-calculation)
     *      The fee is paid in the msg.value of this function. Since the fee is not fixed and might change, the excess amount will be kept in the PufferModule
     *      to the caller from the EigenPod
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function requestConsolidation(bytes32 moduleName, uint256[] calldata srcIndices, uint256[] calldata targetIndices)
        external
        payable;

    /**
     * @notice Skips the next validator for `moduleName`
     * @param moduleName The name of the module
     * @param guardianEOASignatures The signatures of the guardians to validate the skipping of provisioning
     * @dev Restricted to Guardians
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function skipProvisioning(bytes32 moduleName, bytes[] calldata guardianEOASignatures) external;

    /**
     * @notice Batch settling of validator withdrawals
     * @notice Settles a validator withdrawal
     * @dev This is one of the most important methods in the protocol
     *      The withdrawals might be partial or total, and the validator might be downsized or fully exited
     *      It has multiple tasks:
     *      1. Burn the pufETH from the node operator (if the withdrawal amount was lower than 32 ETH * numBatches or completely if the validator was slashed)
     *      2. Burn the Validator Tickets from the node operator (deprecated) and transfer consumed validation time (as WETH) to the PUFFER_REVENUE_DISTRIBUTOR
     *      3. Transfer withdrawal ETH from the PufferModule of the Validator to the PufferVault
     *      4. Decrement the `lockedETHAmount` on the PufferOracle to reflect the new amount of locked ETH
     * @dev If a node operator exits early, will be penalized by the protocol by increasing the totalEpochsValidated so the VT consumption is higher than the actual amount of epochs validated
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function batchHandleWithdrawals(
        StoppedValidatorInfo[] calldata validatorInfos,
        bytes[] calldata guardianEOASignatures,
        uint256 deadline
    ) external payable;
}
