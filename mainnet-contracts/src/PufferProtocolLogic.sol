// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ProtocolStorage } from "./struct/ProtocolStorage.sol";
import { Validator } from "./struct/Validator.sol";
import { Status } from "./struct/Validator.sol";
import { StoppedValidatorInfo } from "./struct/StoppedValidatorInfo.sol";
import { ValidatorKeyData } from "./struct/ValidatorKeyData.sol";
import { PufferProtocolBase } from "./PufferProtocolBase.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { IPufferProtocolLogic } from "./interface/IPufferProtocolLogic.sol";
import { PufferModule } from "./PufferModule.sol";
import { IPufferOracleV2 } from "./interface/IPufferOracleV2.sol";
import { IGuardianModule } from "./interface/IGuardianModule.sol";
import { ValidatorTicket } from "./ValidatorTicket.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";
import { EpochsValidatedSignature } from "./struct/Signatures.sol";
import { InvalidAddress, Unauthorized } from "./Errors.sol";

contract PufferProtocolLogic is PufferProtocolBase, IPufferProtocolLogic {
    using MessageHashUtils for bytes32;

    /**
     * @dev Helper struct for the full withdrawals accounting
     * The amounts of VT and pufETH to burn at the end of the withdrawal
     */
    struct BurnAmounts {
        uint256 vt;
        uint256 pufETH;
    }

    /**
     * @dev Helper struct for the full withdrawals accounting
     * The amounts of pufETH to send to the node operator
     */
    struct Withdrawals {
        uint256 pufETHAmount;
        address node;
        uint256 numBatches;
    }

    constructor(
        PufferVaultV5 pufferVault,
        IGuardianModule guardianModule,
        address moduleManager,
        ValidatorTicket validatorTicket,
        IPufferOracleV2 oracle,
        address beaconDepositContract,
        address payable pufferRevenueDistributor
    )
        PufferProtocolBase(
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
     * @notice Check IPufferProtocol.depositValidationTime
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function depositValidationTime(EpochsValidatedSignature memory epochsValidatedSignature)
        external
        payable
        override
    {
        if (block.timestamp > epochsValidatedSignature.deadline) {
            revert DeadlineExceeded();
        }

        require(epochsValidatedSignature.nodeOperator != address(0), InvalidAddress());
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        uint256 epochCurrentPrice = _PUFFER_ORACLE.getValidatorTicketPrice();
        uint8 operatorNumBatches = $.nodeOperatorInfo[epochsValidatedSignature.nodeOperator].numBatches;
        require(
            msg.value >= operatorNumBatches * _MINIMUM_EPOCHS_VALIDATION_DEPOSIT * epochCurrentPrice
                && msg.value <= operatorNumBatches * _MAXIMUM_EPOCHS_VALIDATION_DEPOSIT * epochCurrentPrice,
            InvalidETHAmount()
        );

        epochsValidatedSignature.functionSelector = IPufferProtocolLogic.depositValidationTime.selector;

        uint256 burnAmount = _useVTOrValidationTime($, epochsValidatedSignature);

        if (burnAmount > 0) {
            _VALIDATOR_TICKET.burn(burnAmount);
        }

        $.nodeOperatorInfo[epochsValidatedSignature.nodeOperator].validationTime += SafeCast.toUint96(msg.value);
        emit ValidationTimeDeposited({ node: epochsValidatedSignature.nodeOperator, ethAmount: msg.value });
    }

    /**
     * @notice Check IPufferProtocol.withdrawValidationTime
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function withdrawValidationTime(uint96 amount, address recipient) external override {
        ProtocolStorage storage $ = _getPufferProtocolStorage();

        // Node operator can only withdraw if they have no active or pending validators
        // In the future, we plan to allow node operators to withdraw VTs even if they have active/pending validators.
        if (
            $.nodeOperatorInfo[msg.sender].activeValidatorCount + $.nodeOperatorInfo[msg.sender].pendingValidatorCount
                != 0
        ) {
            revert ActiveOrPendingValidatorsExist();
        }

        // Reverts if insufficient balance
        // nosemgrep basic-arithmetic-underflow
        $.nodeOperatorInfo[msg.sender].validationTime -= amount;

        // WETH is a contract that has a fallback function that accepts ETH, and never reverts
        address weth = _PUFFER_VAULT.asset();
        weth.call{ value: amount }("");
        // Transfer WETH to the recipient
        ERC20(weth).transfer(recipient, amount);

        emit ValidationTimeWithdrawn(msg.sender, recipient, amount);
    }

    /**
     * @notice Check IPufferProtocol.registerValidatorKey
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function registerValidatorKey(
        ValidatorKeyData calldata data,
        bytes32 moduleName,
        uint256 totalEpochsValidated,
        bytes[] calldata vtConsumptionSignature,
        uint256 deadline
    ) external payable override {
        if (block.timestamp > deadline) {
            revert DeadlineExceeded();
        }

        ProtocolStorage storage $ = _getPufferProtocolStorage();

        _checkValidatorRegistrationInputs({ $: $, data: data, moduleName: moduleName });

        uint256 epochCurrentPrice = _PUFFER_ORACLE.getValidatorTicketPrice();
        uint8 numBatches = data.numBatches;
        uint256 bondAmountEth = _VALIDATOR_BOND * numBatches;

        // The node operator must deposit 1.5 ETH (per batch) or more + minimum validation time for ~30 days
        // At the moment that's roughly 30 days * 225 (there is roughly 225 epochs per day)
        uint256 minimumETHRequired =
            bondAmountEth + (numBatches * _MINIMUM_EPOCHS_VALIDATION_REGISTRATION * epochCurrentPrice);

        require(msg.value >= minimumETHRequired, InvalidETHAmount());

        emit ValidationTimeDeposited({ node: msg.sender, ethAmount: (msg.value - bondAmountEth) });

        _settleVTAccounting({
            $: $,
            epochsValidatedSignature: EpochsValidatedSignature({
                nodeOperator: msg.sender,
                totalEpochsValidated: totalEpochsValidated,
                functionSelector: IPufferProtocolLogic.registerValidatorKey.selector,
                deadline: deadline,
                signatures: vtConsumptionSignature
            }),
            deprecated_burntVTs: 0
        });

        // The bond is converted to pufETH at the current exchange rate
        uint256 pufETHBondAmount = _PUFFER_VAULT.depositETH{ value: bondAmountEth }(address(this));

        uint256 pufferModuleIndex = $.pendingValidatorIndices[moduleName];

        // No need for SafeCast
        $.validators[moduleName][pufferModuleIndex] = Validator({
            pubKey: data.blsPubKey,
            status: Status.PENDING,
            module: address($.modules[moduleName]),
            bond: uint96(pufETHBondAmount),
            node: msg.sender,
            numBatches: numBatches
        });

        // Increment indices for this module and number of validators registered
        unchecked {
            $.nodeOperatorInfo[msg.sender].epochPrice = epochCurrentPrice;
            $.nodeOperatorInfo[msg.sender].validationTime += (msg.value - bondAmountEth);
            ++$.nodeOperatorInfo[msg.sender].pendingValidatorCount;
            ++$.pendingValidatorIndices[moduleName];
            ++$.moduleLimits[moduleName].numberOfRegisteredValidators;
        }

        emit NumberOfRegisteredValidatorsChanged({
            moduleName: moduleName,
            newNumberOfRegisteredValidators: $.moduleLimits[moduleName].numberOfRegisteredValidators
        });
        emit ValidatorKeyRegistered({
            pubKey: data.blsPubKey,
            pufferModuleIndex: pufferModuleIndex,
            moduleName: moduleName,
            numBatches: numBatches
        });
    }

    /**
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function requestConsolidation(bytes32 moduleName, uint256[] calldata srcIndices, uint256[] calldata targetIndices)
        external
        payable
        override
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

        emit ConsolidationRequested(moduleName, srcPubkeys, targetPubkeys);
    }

    /**
     * @notice Check IPufferProtocol.skipProvisioning
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function skipProvisioning(bytes32 moduleName, bytes[] calldata guardianEOASignatures) external override {
        ProtocolStorage storage $ = _getPufferProtocolStorage();

        uint256 skippedIndex = $.nextToBeProvisioned[moduleName];

        address node = $.validators[moduleName][skippedIndex].node;

        // Check the signatures (reverts if invalid)
        _GUARDIAN_MODULE.validateSkipProvisioning({
            moduleName: moduleName,
            skippedIndex: skippedIndex,
            guardianEOASignatures: guardianEOASignatures
        });

        uint256 vtPricePerEpoch = _PUFFER_ORACLE.getValidatorTicketPrice();

        $.nodeOperatorInfo[node].validationTime -=
            ($.vtPenaltyEpochs * vtPricePerEpoch * $.validators[moduleName][skippedIndex].numBatches);
        --$.nodeOperatorInfo[node].pendingValidatorCount;

        // Change the status of that validator
        $.validators[moduleName][skippedIndex].status = Status.SKIPPED;

        // Transfer pufETH to that node operator
        // slither-disable-next-line unchecked-transfer
        _PUFFER_VAULT.transfer(node, $.validators[moduleName][skippedIndex].bond);

        _decreaseNumberOfRegisteredValidators($, moduleName);
        unchecked {
            ++$.nextToBeProvisioned[moduleName];
        }
        emit ValidatorSkipped($.validators[moduleName][skippedIndex].pubKey, skippedIndex, moduleName);
    }

    /**
     * @notice Check IPufferProtocol.batchHandleWithdrawals
     * @dev This function should only be called by the PufferProtocol contract through a delegatecall
     */
    function batchHandleWithdrawals(
        StoppedValidatorInfo[] calldata validatorInfos,
        bytes[] calldata guardianEOASignatures,
        uint256 deadline
    ) external payable override {
        if (block.timestamp > deadline) {
            revert DeadlineExceeded();
        }

        bytes32 messageHash = keccak256(abi.encode(validatorInfos, deadline)).toEthSignedMessageHash();
        bool validSignatures = _GUARDIAN_MODULE.validateGuardiansEOASignatures(guardianEOASignatures, messageHash);
        if (!validSignatures) {
            revert Unauthorized();
        }

        ProtocolStorage storage $ = _getPufferProtocolStorage();

        BurnAmounts memory burnAmounts;
        Withdrawals[] memory bondWithdrawals = new Withdrawals[](validatorInfos.length);

        // 1 batch = 32 ETH
        uint256 numExitedBatches;

        // slither-disable-start calls-loop
        for (uint256 i = 0; i < validatorInfos.length; ++i) {
            Validator storage validator =
                $.validators[validatorInfos[i].moduleName][validatorInfos[i].pufferModuleIndex];

            if (validator.status != Status.ACTIVE) {
                revert InvalidValidatorState(validator.status);
            }

            // Save the Node address for the bond transfer
            bondWithdrawals[i].node = validator.node;
            uint256 bondBurnAmount;

            // We need to scope the variables to avoid stack too deep errors
            {
                uint256 epochValidated = validatorInfos[i].totalEpochsValidated;
                bytes[] memory vtConsumptionSignature = validatorInfos[i].vtConsumptionSignature;
                burnAmounts.vt += _useVTOrValidationTime(
                    $,
                    EpochsValidatedSignature({
                        nodeOperator: bondWithdrawals[i].node,
                        totalEpochsValidated: epochValidated,
                        functionSelector: IPufferProtocolLogic.batchHandleWithdrawals.selector,
                        deadline: deadline,
                        signatures: vtConsumptionSignature
                    })
                );
            }

            if (validatorInfos[i].isDownsize) {
                // We update the bondWithdrawals
                (bondWithdrawals[i].pufETHAmount, bondWithdrawals[i].numBatches) =
                    _downsizeValidators($, validatorInfos[i], validator);

                numExitedBatches += bondWithdrawals[i].numBatches;
            } else {
                // Full validator exit
                numExitedBatches += validator.numBatches;
                bondWithdrawals[i].numBatches = validator.numBatches > 0 ? validator.numBatches : 1;

                // We update the bondWithdrawals
                (bondBurnAmount, bondWithdrawals[i].pufETHAmount, bondWithdrawals[i].numBatches) =
                    _exitValidator($, validatorInfos[i], validator);
            }

            // Update the burnAmounts
            burnAmounts.pufETH += bondBurnAmount;
        }

        if (burnAmounts.vt > 0) {
            _VALIDATOR_TICKET.burn(burnAmounts.vt);
        }
        if (burnAmounts.pufETH > 0) {
            // Because we've calculated everything in the previous loop, we can do the burning
            _PUFFER_VAULT.burn(burnAmounts.pufETH);
        }

        // Deduct 32 ETH per batch from the `lockedETHAmount` on the PufferOracle
        _PUFFER_ORACLE.exitValidators(numExitedBatches);

        batchHandleWithdrawalsAccounting(bondWithdrawals, validatorInfos);
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
    function _settleVTAccounting(
        ProtocolStorage storage $,
        EpochsValidatedSignature memory epochsValidatedSignature,
        uint256 deprecated_burntVTs
    ) internal {
        address node = epochsValidatedSignature.nodeOperator;
        // There is nothing to settle if this is the first validator for the node operator
        if ($.nodeOperatorInfo[node].activeValidatorCount + $.nodeOperatorInfo[node].pendingValidatorCount == 0) {
            return;
        }

        bytes32 messageHash = keccak256(
            abi.encode(
                node,
                epochsValidatedSignature.totalEpochsValidated,
                _useNonce(epochsValidatedSignature.functionSelector, node),
                epochsValidatedSignature.deadline
            )
        ).toEthSignedMessageHash();

        bool validSignatures =
            _GUARDIAN_MODULE.validateGuardiansEOASignatures(epochsValidatedSignature.signatures, messageHash);

        if (!validSignatures) {
            revert Unauthorized();
        }

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

        emit ValidationTimeConsumed({
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
    function _useVTOrValidationTime(ProtocolStorage storage $, EpochsValidatedSignature memory epochsValidatedSignature)
        internal
        returns (uint256 vtAmountToBurn)
    {
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

                emit ValidationTimeConsumed({ node: nodeOperator, consumedAmount: 0, deprecated_burntVTs: vtBurnAmount });

                return vtAmountToBurn;
            }

            // If the node operator has less VT than the amount to burn, we burn all of it, and we use the validation time
            vtAmountToBurn = nodeVTBalance;
            // nosemgrep basic-arithmetic-underflow
            $.nodeOperatorInfo[nodeOperator].deprecated_vtBalance -= SafeCast.toUint96(nodeVTBalance);
        }

        // If the node operator has no VT, we use the validation time
        _settleVTAccounting({
            $: $,
            epochsValidatedSignature: epochsValidatedSignature,
            deprecated_burntVTs: nodeVTBalance
        });
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

    function batchHandleWithdrawalsAccounting(
        Withdrawals[] memory bondWithdrawals,
        StoppedValidatorInfo[] calldata validatorInfos
    ) internal {
        // In this loop, we transfer back the bonds, and do the accounting that affects the exchange rate
        for (uint256 i = 0; i < validatorInfos.length; ++i) {
            // If the withdrawal amount is bigger than 32 ETH * numBatches, we cap it to 32 ETH * numBatches
            // The excess is the rewards amount for that Node Operator
            uint256 transferAmount = validatorInfos[i].withdrawalAmount > (32 ether * bondWithdrawals[i].numBatches)
                ? 32 ether * bondWithdrawals[i].numBatches
                : validatorInfos[i].withdrawalAmount;
            //solhint-disable-next-line avoid-low-level-calls
            (bool success,) =
                PufferModule(payable(validatorInfos[i].module)).call(address(_PUFFER_VAULT), transferAmount, "");
            if (!success) {
                revert Failed();
            }

            // Skip the empty transfer (validator got slashed)
            if (bondWithdrawals[i].pufETHAmount == 0) {
                continue;
            }
            // slither-disable-next-line unchecked-transfer
            _PUFFER_VAULT.transfer(bondWithdrawals[i].node, bondWithdrawals[i].pufETHAmount);
        }
        // slither-disable-start calls-loop
    }

    function _downsizeValidators(
        ProtocolStorage storage $,
        StoppedValidatorInfo calldata validatorInfo,
        Validator storage validator
    ) internal returns (uint256 exitingBond, uint256 exitedBatches) {
        exitedBatches = validatorInfo.withdrawalAmount / 32 ether;

        uint256 numBatchesBefore = validator.numBatches;

        // We burn the bond according to previous burn rate (before downsize)
        uint256 burnAmount = _getBondBurnAmount({
            validatorInfo: validatorInfo,
            validatorBondAmount: validator.bond,
            numBatches: numBatchesBefore
        });

        exitingBond = (validator.bond * exitedBatches) / validator.numBatches;

        // The burned amount is subtracted from the exiting bond, so the remaining bond is kept in full
        // The backend must prevent any downsize that would result in a burned amount greater than the exiting bond
        require(exitingBond >= burnAmount, InvalidWithdrawAmount());
        exitingBond -= burnAmount;

        emit ValidatorDownsized({
            pubKey: validator.pubKey,
            pufferModuleIndex: validatorInfo.pufferModuleIndex,
            moduleName: validatorInfo.moduleName,
            pufETHBurnAmount: burnAmount,
            epoch: validatorInfo.totalEpochsValidated,
            numBatchesBefore: numBatchesBefore,
            numBatchesAfter: validator.numBatches - exitedBatches
        });

        $.nodeOperatorInfo[validator.node].numBatches -= SafeCast.toUint8(exitedBatches);

        validator.bond -= SafeCast.toUint96(exitingBond);
        validator.numBatches -= SafeCast.toUint8(exitedBatches);

        return (exitingBond, exitedBatches);
    }

    function _exitValidator(
        ProtocolStorage storage $,
        StoppedValidatorInfo calldata validatorInfo,
        Validator storage validator
    ) internal returns (uint256 bondBurnAmount, uint256 bondReturnAmount, uint256 exitedBatches) {
        uint96 bondAmount = validator.bond;
        uint256 numBatches = validator.numBatches;

        // Get the bondBurnAmount for the withdrawal at the current exchange rate
        bondBurnAmount = _getBondBurnAmount({
            validatorInfo: validatorInfo,
            validatorBondAmount: bondAmount,
            numBatches: validator.numBatches
        });

        emit ValidatorExited({
            pubKey: validator.pubKey,
            pufferModuleIndex: validatorInfo.pufferModuleIndex,
            moduleName: validatorInfo.moduleName,
            pufETHBurnAmount: bondBurnAmount,
            numBatches: numBatches
        });

        // Decrease the number of registered validators for that module
        _decreaseNumberOfRegisteredValidators($, validatorInfo.moduleName);

        // Storage VT and the active validator count update for the Node Operator
        // nosemgrep basic-arithmetic-underflow
        --$.nodeOperatorInfo[validator.node].activeValidatorCount;
        $.nodeOperatorInfo[validator.node].numBatches -= validator.numBatches;

        delete $.validators[validatorInfo.moduleName][
            validatorInfo.pufferModuleIndex
        ];
        // nosemgrep basic-arithmetic-underflow
        return (bondBurnAmount, bondAmount - bondBurnAmount, numBatches);
    }

    function _decreaseNumberOfRegisteredValidators(ProtocolStorage storage $, bytes32 moduleName) internal {
        --$.moduleLimits[moduleName].numberOfRegisteredValidators;
        emit NumberOfRegisteredValidatorsChanged(moduleName, $.moduleLimits[moduleName].numberOfRegisteredValidators);
    }

    function _getBondBurnAmount(
        StoppedValidatorInfo calldata validatorInfo,
        uint256 validatorBondAmount,
        uint256 numBatches
    ) internal view returns (uint256 pufETHBurnAmount) {
        // Case 1:
        // The Validator was slashed, we burn the whole bond for that validator
        if (validatorInfo.wasSlashed) {
            return validatorBondAmount;
        }

        // Case 2:
        // The withdrawal amount is less than 32 ETH * numBatches, we burn the difference to cover up the loss for inactivity
        if (validatorInfo.withdrawalAmount < (uint256(32 ether) * numBatches)) {
            pufETHBurnAmount =
                _PUFFER_VAULT.convertToSharesUp((uint256(32 ether) * numBatches) - validatorInfo.withdrawalAmount);
        }

        // Case 3:
        // Withdrawal amount was >= 32 ETH * numBatches, we don't burn anything
        return pufETHBurnAmount;
    }

    function _checkValidatorRegistrationInputs(
        ProtocolStorage storage $,
        ValidatorKeyData calldata data,
        bytes32 moduleName
    ) internal view {
        // Check number of batches between 1 (32 ETH) and 64 (2048 ETH)
        require(0 < data.numBatches && data.numBatches < 65, InvalidNumberOfBatches());

        // This acts as a validation if the module is existent
        // +1 is to validate the current transaction registration
        require(
            ($.moduleLimits[moduleName].numberOfRegisteredValidators + 1) <= $.moduleLimits[moduleName].allowedLimit,
            ValidatorLimitForModuleReached()
        );

        require(data.blsPubKey.length == _BLS_PUB_KEY_LENGTH, InvalidBLSPubKey());
    }
}
