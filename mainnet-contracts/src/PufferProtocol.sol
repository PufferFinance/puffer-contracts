// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PufferProtocolStorage } from "./PufferProtocolStorage.sol";
import { PufferModuleManager } from "./PufferModuleManager.sol";
import { IPufferOracleV2 } from "./interface/IPufferOracleV2.sol";
import { IGuardianModule } from "./interface/IGuardianModule.sol";
import { IBeaconDepositContract } from "./interface/IBeaconDepositContract.sol";
import { ValidatorKeyData } from "./struct/ValidatorKeyData.sol";
import { Validator } from "./struct/Validator.sol";
import { Permit } from "./structs/Permit.sol";
import { Status } from "./struct/Status.sol";
import { WithdrawalType } from "./struct/WithdrawalType.sol";
import { ProtocolStorage, NodeInfo, ModuleLimit } from "./struct/ProtocolStorage.sol";
import { LibBeaconchainContract } from "./LibBeaconchainContract.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";
import { ValidatorTicket } from "./ValidatorTicket.sol";
import { InvalidAddress } from "./Errors.sol";
import { StoppedValidatorInfo } from "./struct/StoppedValidatorInfo.sol";
import { PufferModule } from "./PufferModule.sol";
import { ProtocolSignatureNonces } from "./ProtocolSignatureNonces.sol";
import { EpochsValidatedSignature } from "./struct/Signatures.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ProtocolConstants } from "./ProtocolConstants.sol";
import { IPufferProtocolLogic } from "./interface/IPufferProtocolLogic.sol";

/**
 * @title PufferProtocol
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 * @dev Upgradeable smart contract for the Puffer Protocol
 * Storage variables are located in PufferProtocolStorage.sol
 */
contract PufferProtocol is
    IPufferProtocol,
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    PufferProtocolStorage,
    ProtocolSignatureNonces,
    ProtocolConstants
{
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

    receive() external payable { }

    /**
     * @notice Initializes the contract
     */
    function initialize(address accessManager, address pufferProtocolLogic) external initializer {
        if (address(accessManager) == address(0)) {
            revert InvalidAddress();
        }
        __AccessManaged_init(accessManager);
        _createPufferModule(_PUFFER_MODULE_0);
        _changeMinimumVTAmount(30 * _EPOCHS_PER_DAY); // 30 days worth of ETH is the minimum VT amount
        _setVTPenalty(10 * _EPOCHS_PER_DAY); // 10 days worth of ETH is the VT penalty
        _setPufferProtocolLogic(pufferProtocolLogic);
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     * @dev DEPRECATED - This method is deprecated and will be removed in the future upgrade
     */
    function depositValidatorTickets(Permit calldata permit, address node) external restricted {
        if (node == address(0)) {
            revert InvalidAddress();
        }
        // owner: msg.sender is intentional
        // We only want the owner of the Permit signature to be able to deposit using the signature
        // For an invalid signature, the permit will revert, but it is wrapped in try/catch, meaning the transaction execution
        // will continue. If the `msg.sender` did a `VALIDATOR_TICKET.approve(spender, amount)` before calling this
        // And the spender is `msg.sender` the Permit call will revert, but the overall transaction will succeed
        _callPermit(address(_VALIDATOR_TICKET), permit);

        // slither-disable-next-line unchecked-transfer
        _VALIDATOR_TICKET.transferFrom(msg.sender, address(this), permit.amount);

        ProtocolStorage storage $ = _getPufferProtocolStorage();
        $.nodeOperatorInfo[node].deprecated_vtBalance += SafeCast.toUint96(permit.amount);
        emit ValidatorTicketsDeposited(node, msg.sender, permit.amount);
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function depositValidationTime(EpochsValidatedSignature memory epochsValidatedSignature)
        external
        payable
        restricted
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

        epochsValidatedSignature.functionSelector = _FUNCTION_SELECTOR_DEPOSIT_VALIDATION_TIME;

        uint256 burnAmount = _useVTOrValidationTime({ $: $, epochsValidatedSignature: epochsValidatedSignature });

        if (burnAmount > 0) {
            _VALIDATOR_TICKET.burn(burnAmount);
        }

        $.nodeOperatorInfo[epochsValidatedSignature.nodeOperator].validationTime += SafeCast.toUint96(msg.value);
        emit ValidationTimeDeposited({ node: epochsValidatedSignature.nodeOperator, ethAmount: msg.value });
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     * @dev DEPRECATED - This method is deprecated and will be removed in the future upgrade
     */
    function withdrawValidatorTickets(uint96 amount, address recipient) external restricted {
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
        $.nodeOperatorInfo[msg.sender].deprecated_vtBalance -= amount;

        // slither-disable-next-line unchecked-transfer
        _VALIDATOR_TICKET.transfer(recipient, amount);

        emit ValidatorTicketsWithdrawn(msg.sender, recipient, amount);
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function withdrawValidationTime(uint96 amount, address recipient) external restricted {
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
     * @inheritdoc IPufferProtocol
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function registerValidatorKey(
        ValidatorKeyData calldata data,
        bytes32 moduleName,
        uint256 totalEpochsValidated,
        bytes[] calldata vtConsumptionSignature,
        uint256 deadline
    ) external payable restricted {
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
                functionSelector: _FUNCTION_SELECTOR_REGISTER_VALIDATOR_KEY,
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
     * @inheritdoc IPufferProtocol
     * @dev Restricted to Puffer Paymaster
     */
    function provisionNode(bytes calldata validatorSignature, bytes32 depositRootHash) external restricted {
        if (depositRootHash != _BEACON_DEPOSIT_CONTRACT.get_deposit_root()) {
            revert InvalidDepositRootHash();
        }

        ProtocolStorage storage $ = _getPufferProtocolStorage();

        (bytes32 moduleName, uint256 index) = getNextValidatorToProvision();

        // Increment next validator to be provisioned index, panics if there is no validator for provisioning
        $.nextToBeProvisioned[moduleName] = index + 1;
        unchecked {
            // Increment module selection index
            ++$.moduleSelectIndex;
        }

        _validateSignaturesAndProvisionValidator({
            $: $,
            moduleName: moduleName,
            index: index,
            validatorSignature: validatorSignature
        });

        // Update Node Operator info
        address node = $.validators[moduleName][index].node;
        --$.nodeOperatorInfo[node].pendingValidatorCount;
        ++$.nodeOperatorInfo[node].activeValidatorCount;

        // Update numBatches now that validator becomes active
        $.nodeOperatorInfo[node].numBatches += $.validators[moduleName][index].numBatches;

        // Mark the validator as active
        $.validators[moduleName][index].status = Status.ACTIVE;
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted to Node Operators
     */
    function requestConsolidation(bytes32 moduleName, uint256[] calldata srcIndices, uint256[] calldata targetIndices)
        external
        payable
        restricted
    {
        bytes memory callData = abi.encodeWithSelector(
            IPufferProtocolLogic._requestConsolidation.selector, moduleName, srcIndices, targetIndices
        );

        (bool success, bytes memory result) = _getPufferProtocolStorage().pufferProtocolLogic.delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted to Node Operators
     */
    function requestWithdrawal(
        bytes32 moduleName,
        uint256[] calldata indices,
        uint64[] calldata gweiAmounts,
        WithdrawalType[] calldata withdrawalType,
        bytes[][] calldata validatorAmountsSignatures,
        uint256 deadline
    ) external payable restricted {
        if (block.timestamp > deadline) {
            revert DeadlineExceeded();
        }

        ProtocolStorage storage $ = _getPufferProtocolStorage();

        bytes[] memory pubkeys = new bytes[](indices.length);

        // validate pubkeys belong to that node and are active
        for (uint256 i = 0; i < indices.length; ++i) {
            Validator memory validator = $.validators[moduleName][indices[i]];
            require(validator.node == msg.sender, InvalidValidator());
            pubkeys[i] = validator.pubKey;

            if (withdrawalType[i] == WithdrawalType.EXIT_VALIDATOR) {
                require(gweiAmounts[i] == 0, InvalidWithdrawAmount());
            } else {
                if (withdrawalType[i] == WithdrawalType.DOWNSIZE) {
                    uint256 batches = gweiAmounts[i] / _32_ETH_GWEI;
                    require(
                        batches > validator.numBatches && gweiAmounts[i] % _32_ETH_GWEI == 0, InvalidWithdrawAmount()
                    );
                }

                // If downsize or rewards withdrawal, backend needs to validate the amount

                _GUARDIAN_MODULE.validateWithdrawalRequest({
                    node: msg.sender,
                    pubKey: pubkeys[i],
                    gweiAmount: gweiAmounts[i],
                    nonce: _useNonce(_FUNCTION_SELECTOR_REQUEST_WITHDRAWAL, msg.sender),
                    deadline: deadline,
                    guardianEOASignatures: validatorAmountsSignatures[i]
                });
            }
        }

        _PUFFER_MODULE_MANAGER.requestWithdrawal{ value: msg.value }(moduleName, pubkeys, gweiAmounts);
    }

    function _batchHandleWithdrawalsAccounting(
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

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted to Puffer Paymaster
     */
    function batchHandleWithdrawals(
        StoppedValidatorInfo[] calldata validatorInfos,
        bytes[] calldata guardianEOASignatures,
        uint256 deadline
    ) external restricted {
        if (block.timestamp > deadline) {
            revert DeadlineExceeded();
        }

        _GUARDIAN_MODULE.validateBatchWithdrawals(validatorInfos, guardianEOASignatures, deadline);

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
                        functionSelector: _FUNCTION_SELECTOR_BATCH_HANDLE_WITHDRAWALS,
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

        _batchHandleWithdrawalsAccounting(bondWithdrawals, validatorInfos);
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted to Puffer Paymaster
     */
    function skipProvisioning(bytes32 moduleName, bytes[] calldata guardianEOASignatures) external restricted {
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
     * @dev Restricted to the DAO
     */
    function changeMinimumVTAmount(uint256 newMinimumVTAmount) external restricted {
        _changeMinimumVTAmount(newMinimumVTAmount);
    }

    /**
     * @dev Initially it is restricted to the DAO
     */
    function createPufferModule(bytes32 moduleName) external restricted returns (address) {
        return _createPufferModule(moduleName);
    }

    /**
     * @dev Restricted to the DAO
     */
    function setModuleWeights(bytes32[] calldata newModuleWeights) external restricted {
        _setModuleWeights(newModuleWeights);
    }

    /**
     * @dev Restricted to the DAO
     */
    function setValidatorLimitPerModule(bytes32 moduleName, uint128 limit) external restricted {
        _setValidatorLimitPerModule(moduleName, limit);
    }

    /**
     * @dev Restricted to the DAO
     */
    function setVTPenalty(uint256 newPenaltyAmount) external restricted {
        _setVTPenalty(newPenaltyAmount);
    }

    /**
     * @dev Restricted to the DAO
     */
    function setPufferProtocolLogic(address newPufferProtocolLogic) external restricted {
        _setPufferProtocolLogic(newPufferProtocolLogic);
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getVTPenalty() external view returns (uint256) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.vtPenaltyEpochs;
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getDepositDataRoot(bytes calldata pubKey, bytes calldata signature, bytes calldata withdrawalCredentials)
        external
        pure
        returns (bytes32)
    {
        return LibBeaconchainContract.getDepositDataRoot(pubKey, signature, withdrawalCredentials);
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev This is meant for OFF-CHAIN use, as it can be very expensive to call
     */
    function getValidators(bytes32 moduleName) external view returns (Validator[] memory) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();

        uint256 numOfValidators = $.pendingValidatorIndices[moduleName];

        Validator[] memory validators = new Validator[](numOfValidators);

        for (uint256 i = 0; i < numOfValidators; ++i) {
            validators[i] = $.validators[moduleName][i];
        }

        return validators;
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getNextValidatorToProvision() public view returns (bytes32, uint256) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();

        uint256 moduleSelectionIndex = $.moduleSelectIndex;
        uint256 moduleWeightsLength = $.moduleWeights.length;
        // Do Weights number of rounds
        uint256 moduleEndIndex = moduleSelectionIndex + moduleWeightsLength;

        // Read from the storage
        bytes32 moduleName = $.moduleWeights[moduleSelectionIndex % moduleWeightsLength];

        // Iterate through all modules to see if there is a validator ready to be provisioned
        while (moduleSelectionIndex < moduleEndIndex) {
            // Read the index for that moduleName
            uint256 pufferModuleIndex = $.nextToBeProvisioned[moduleName];

            // If we find it, return it
            if ($.validators[moduleName][pufferModuleIndex].status == Status.PENDING) {
                return (moduleName, pufferModuleIndex);
            }
            unchecked {
                // If not, try the next module
                ++moduleSelectionIndex;
            }
            moduleName = $.moduleWeights[moduleSelectionIndex % moduleWeightsLength];
        }

        // No validators found
        return (bytes32("NO_VALIDATORS"), type(uint256).max);
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getNextValidatorToBeProvisionedIndex(bytes32 moduleName) external view returns (uint256) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.nextToBeProvisioned[moduleName];
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getPendingValidatorIndex(bytes32 moduleName) external view returns (uint256) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.pendingValidatorIndices[moduleName];
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getValidatorInfo(bytes32 moduleName, uint256 pufferModuleIndex) external view returns (Validator memory) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.validators[moduleName][pufferModuleIndex];
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getNodeInfo(address node) external view returns (NodeInfo memory) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.nodeOperatorInfo[node];
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getModuleAddress(bytes32 moduleName) external view returns (address) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return address($.modules[moduleName]);
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getWithdrawalCredentials(address module) public view returns (bytes memory) {
        return PufferModule(payable(module)).getWithdrawalCredentials();
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getModuleWeights() external view returns (bytes32[] memory) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.moduleWeights;
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getModuleSelectIndex() external view returns (uint256) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.moduleSelectIndex;
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev DEPRECATED - This method is deprecated and will be removed in the future upgrade
     */
    function getValidatorTicketsBalance(address owner) public view returns (uint256) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.nodeOperatorInfo[owner].deprecated_vtBalance;
    }

    function getValidationTime(address owner) public view returns (uint256) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.nodeOperatorInfo[owner].validationTime;
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getMinimumVtAmount() public view returns (uint256) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.minimumVtAmount;
    }

    /**
     * @inheritdoc IPufferProtocol
     */
    function getModuleLimitInformation(bytes32 moduleName) external view returns (ModuleLimit memory info) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        return $.moduleLimits[moduleName];
    }

    /**
     * @notice Called by the PufferModules to check if the system is paused
     * @dev `restricted` will revert if the system is paused
     */
    function revertIfPaused() external restricted { }

    function _setValidatorLimitPerModule(bytes32 moduleName, uint128 limit) internal {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        if (limit < $.moduleLimits[moduleName].numberOfRegisteredValidators) {
            revert ValidatorLimitForModuleReached();
        }
        emit ValidatorLimitPerModuleChanged($.moduleLimits[moduleName].allowedLimit, limit);
        $.moduleLimits[moduleName].allowedLimit = limit;
    }

    function _setVTPenalty(uint256 newPenaltyAmount) internal {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        if (newPenaltyAmount > $.minimumVtAmount) {
            revert InvalidVTAmount();
        }
        emit VTPenaltyChanged($.vtPenaltyEpochs, newPenaltyAmount);
        $.vtPenaltyEpochs = newPenaltyAmount;
    }

    function _setModuleWeights(bytes32[] memory newModuleWeights) internal {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        emit ModuleWeightsChanged($.moduleWeights, newModuleWeights);
        $.moduleWeights = newModuleWeights;
    }

    function _createPufferModule(bytes32 moduleName) internal returns (address) {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        if (address($.modules[moduleName]) != address(0)) {
            revert ModuleAlreadyExists();
        }
        PufferModule module = _PUFFER_MODULE_MANAGER.createNewPufferModule(moduleName);
        $.modules[moduleName] = module;
        $.moduleWeights.push(moduleName);
        bytes32 withdrawalCredentials = bytes32(module.getWithdrawalCredentials());
        emit NewPufferModuleCreated(address(module), moduleName, withdrawalCredentials);
        _setValidatorLimitPerModule(moduleName, 500);
        return address(module);
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

    function _changeMinimumVTAmount(uint256 newMinimumVtAmount) internal {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        if (newMinimumVtAmount < $.vtPenaltyEpochs) {
            revert InvalidVTAmount();
        }
        emit MinimumVTAmountChanged($.minimumVtAmount, newMinimumVtAmount);
        $.minimumVtAmount = newMinimumVtAmount;
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

    function _validateSignaturesAndProvisionValidator(
        ProtocolStorage storage $,
        bytes32 moduleName,
        uint256 index,
        bytes calldata validatorSignature
    ) internal {
        bytes memory validatorPubKey = $.validators[moduleName][index].pubKey;
        uint256 numBatches = $.validators[moduleName][index].numBatches;

        bytes memory withdrawalCredentials = getWithdrawalCredentials($.validators[moduleName][index].module);

        bytes32 depositDataRoot =
            LibBeaconchainContract.getDepositDataRoot(validatorPubKey, validatorSignature, withdrawalCredentials);

        PufferModule module = $.modules[moduleName];

        // Transfer 32 ETH to this contract for each batch
        _PUFFER_VAULT.transferETH(address(this), numBatches * 32 ether);

        emit SuccessfullyProvisioned(validatorPubKey, index, moduleName, numBatches);

        // Increase lockedETH on Puffer Oracle
        for (uint256 i = 0; i < numBatches; ++i) {
            _PUFFER_ORACLE.provisionNode();
        }

        _BEACON_DEPOSIT_CONTRACT.deposit{ value: numBatches * 32 ether }(
            validatorPubKey, module.getWithdrawalCredentials(), validatorSignature, depositDataRoot
        );
    }

    /**
     * @dev Internal function to return the deprecated validator tickets burn amount
     *      and/or consume the validation time from the node operator
     * @dev The deprecated vt balance is reduced here but the actual VT is not burned here (for efficiency)
     * @param $ The protocol storage
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
        bytes memory callData =
            abi.encodeWithSelector(IPufferProtocolLogic._useVTOrValidationTime.selector, epochsValidatedSignature);
        (bool success, bytes memory result) = $.pufferProtocolLogic.delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        vtAmountToBurn = abi.decode(result, (uint256));
    }

    /**
     * @dev Internal function to settle the VT accounting for a node operator
     * @param $ The protocol storage
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
        bytes memory callData = abi.encodeWithSelector(
            IPufferProtocolLogic._settleVTAccounting.selector, epochsValidatedSignature, deprecated_burntVTs
        );

        (bool success, bytes memory result) = $.pufferProtocolLogic.delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _callPermit(address token, Permit calldata permitData) internal {
        try IERC20Permit(token).permit({
            owner: msg.sender,
            spender: address(this),
            value: permitData.amount,
            deadline: permitData.deadline,
            v: permitData.v,
            s: permitData.s,
            r: permitData.r
        }) { } catch { }
    }

    function _decreaseNumberOfRegisteredValidators(ProtocolStorage storage $, bytes32 moduleName) internal {
        --$.moduleLimits[moduleName].numberOfRegisteredValidators;
        emit NumberOfRegisteredValidatorsChanged(moduleName, $.moduleLimits[moduleName].numberOfRegisteredValidators);
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

    function _setPufferProtocolLogic(address newPufferProtocolLogic) internal {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        emit PufferProtocolLogicSet($.pufferProtocolLogic, newPufferProtocolLogic);
        $.pufferProtocolLogic = newPufferProtocolLogic;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }

    function getPufferProtocolLogic() external view returns (address) {
        return _getPufferProtocolStorage().pufferProtocolLogic;
    }

    function GUARDIAN_MODULE() external view override returns (IGuardianModule) {
        return _GUARDIAN_MODULE;
    }

    function VALIDATOR_TICKET() external view override returns (ValidatorTicket) {
        return _VALIDATOR_TICKET;
    }

    function PUFFER_VAULT() external view override returns (PufferVaultV5) {
        return _PUFFER_VAULT;
    }

    function PUFFER_MODULE_MANAGER() external view override returns (PufferModuleManager) {
        return _PUFFER_MODULE_MANAGER;
    }

    function PUFFER_ORACLE() external view override returns (IPufferOracleV2) {
        return _PUFFER_ORACLE;
    }

    function BEACON_DEPOSIT_CONTRACT() external view override returns (IBeaconDepositContract) {
        return _BEACON_DEPOSIT_CONTRACT;
    }

    function PUFFER_REVENUE_DISTRIBUTOR() external view override returns (address payable) {
        return _PUFFER_REVENUE_DISTRIBUTOR;
    }
}
