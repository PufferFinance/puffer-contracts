// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PufferProtocolStorage } from "./PufferProtocolStorage.sol";
import { ProtocolStorage } from "./struct/ProtocolStorage.sol";
import { ProtocolSignatureNonces } from "./ProtocolSignatureNonces.sol";
import { Validator } from "./struct/Validator.sol";
import { Status } from "./struct/Validator.sol";
import { ProtocolConstants } from "./ProtocolConstants.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { PufferModuleManager } from "./PufferModuleManager.sol";
import { IPufferOracleV2 } from "./interface/IPufferOracleV2.sol";
import { IGuardianModule } from "./interface/IGuardianModule.sol";
import { IBeaconDepositContract } from "./interface/IBeaconDepositContract.sol";
import { ValidatorTicket } from "./ValidatorTicket.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";
import { EpochsValidatedSignature } from "./struct/Signatures.sol";

contract PufferProtocolLogic is PufferProtocolStorage, ProtocolSignatureNonces, ProtocolConstants {
    constructor(
        PufferVaultV5 pufferVault,
        IGuardianModule guardianModule,
        address moduleManager,
        ValidatorTicket validatorTicket,
        IPufferOracleV2 oracle,
        address beaconDepositContract,
        address payable pufferRevenueDistributor
    )
        ProtocolConstants(
            pufferVault,
            guardianModule,
            moduleManager,
            validatorTicket,
            oracle,
            beaconDepositContract,
            pufferRevenueDistributor
        )
    { }

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
        returns (uint256 vtAmountToBurn)
    {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        address nodeOperator = epochsValidatedSignature.nodeOperator;
        uint256 previousTotalEpochsValidated = $.nodeOperatorInfo[nodeOperator].totalEpochsValidated;

        if (previousTotalEpochsValidated == epochsValidatedSignature.totalEpochsValidated) {
            return 0;
        }
        require(
            previousTotalEpochsValidated < epochsValidatedSignature.totalEpochsValidated, InvalidTotalEpochsValidated()
        );

        // Burn the VT first, then fallback to ETH from the node operator
        uint256 nodeVTBalance = $.nodeOperatorInfo[nodeOperator].deprecated_vtBalance;

        // If the node operator has VT, we burn it first
        if (nodeVTBalance > 0) {
            uint256 vtBurnAmount =
                _getVTBurnAmount(epochsValidatedSignature.totalEpochsValidated - previousTotalEpochsValidated);
            if (nodeVTBalance >= vtBurnAmount) {
                // Burn the VT first, and update the node operator VT balance
                vtAmountToBurn = vtBurnAmount;
                // nosemgrep basic-arithmetic-underflow
                $.nodeOperatorInfo[nodeOperator].deprecated_vtBalance -= SafeCast.toUint96(vtBurnAmount);

                emit IPufferProtocol.ValidationTimeConsumed({
                    node: nodeOperator,
                    consumedAmount: 0,
                    deprecated_burntVTs: vtBurnAmount
                });

                return vtAmountToBurn;
            }

            // If the node operator has less VT than the amount to burn, we burn all of it, and we use the validation time
            vtAmountToBurn = nodeVTBalance;
            // nosemgrep basic-arithmetic-underflow
            $.nodeOperatorInfo[nodeOperator].deprecated_vtBalance -= SafeCast.toUint96(nodeVTBalance);
        }

        // If the node operator has no VT, we use the validation time
        _settleVTAccounting({ epochsValidatedSignature: epochsValidatedSignature, deprecated_burntVTs: nodeVTBalance });
    }

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
        public
        payable
    {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        address node = epochsValidatedSignature.nodeOperator;
        // There is nothing to settle if this is the first validator for the node operator
        if ($.nodeOperatorInfo[node].activeValidatorCount + $.nodeOperatorInfo[node].pendingValidatorCount == 0) {
            return;
        }

        _GUARDIAN_MODULE.validateTotalEpochsValidated({
            node: node,
            totalEpochsValidated: epochsValidatedSignature.totalEpochsValidated,
            nonce: _useNonce(epochsValidatedSignature.functionSelector, node),
            deadline: epochsValidatedSignature.deadline,
            guardianEOASignatures: epochsValidatedSignature.signatures
        });

        uint256 epochCurrentPrice = _PUFFER_ORACLE.getValidatorTicketPrice();

        uint256 meanPrice = ($.nodeOperatorInfo[node].epochPrice + epochCurrentPrice) / 2;

        uint256 previousTotalEpochsValidated = $.nodeOperatorInfo[node].totalEpochsValidated;

        // convert burned validator tickets to epochs
        uint256 epochsBurntFromDeprecatedVT = (deprecated_burntVTs * 225) / 1 ether; // 1 VT = 1 DAY. 1 DAY = 225 Epochs

        uint256 validationTimeToConsume = (
            epochsValidatedSignature.totalEpochsValidated - previousTotalEpochsValidated - epochsBurntFromDeprecatedVT
        ) * meanPrice;

        // Update the current epoch VT price for the node operator
        $.nodeOperatorInfo[node].epochPrice = epochCurrentPrice;
        $.nodeOperatorInfo[node].totalEpochsValidated = epochsValidatedSignature.totalEpochsValidated;
        $.nodeOperatorInfo[node].validationTime -= validationTimeToConsume;

        emit IPufferProtocol.ValidationTimeConsumed({
            node: node,
            consumedAmount: validationTimeToConsume,
            deprecated_burntVTs: deprecated_burntVTs
        });

        address weth = _PUFFER_VAULT.asset();

        // WETH is a contract that has a fallback function that accepts ETH, and never reverts
        weth.call{ value: validationTimeToConsume }("");

        // Transfer WETH to the Revenue Distributor, it will be slow released to the PufferVault
        ERC20(weth).transfer(_PUFFER_REVENUE_DISTRIBUTOR, validationTimeToConsume);
    }

    /**
     * @dev Internal function to get the amount of VT to burn during a number of epochs
     * @param validatedEpochs The number of epochs validated by the node operator (not necessarily the total epochs)
     * @return vtBurnAmount The amount of VT to burn
     */
    function _getVTBurnAmount(uint256 validatedEpochs) internal pure returns (uint256) {
        // Epoch has 32 blocks, each block is 12 seconds, we upscale to 18 decimals to get the VT amount and divide by 1 day
        // The formula is validatedEpochs * 32 * 12 * 1 ether / 1 days (4444444444444444.44444444...) we round it up
        return validatedEpochs * 4444444444444445;
    }
}
