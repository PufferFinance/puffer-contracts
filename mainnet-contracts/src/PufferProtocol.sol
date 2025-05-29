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
import { ProtocolStorage, NodeInfo, ModuleLimit } from "./struct/ProtocolStorage.sol";
import { LibBeaconchainContract } from "./LibBeaconchainContract.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";
import { ValidatorTicket } from "./ValidatorTicket.sol";
import { InvalidAddress } from "./Errors.sol";
import { StoppedValidatorInfo } from "./struct/StoppedValidatorInfo.sol";
import { PufferModule } from "./PufferModule.sol";
import { NoncesUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
    NoncesUpgradeable
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
    }

    /**
     * @dev BLS public keys are 48 bytes long
     */
    uint256 internal constant _BLS_PUB_KEY_LENGTH = 48;

    /**
     * @dev ETH Amount required to be deposited as a bond
     */
    uint256 internal constant _VALIDATOR_BOND = 1.5 ether;

    /**
     * @dev Minimum validation time in epochs
     * Roughly: 30 days * 225 epochs per day = 6750 epochs
     */
    uint256 internal constant _MINIMUM_EPOCHS_VALIDATION = 6750;

    /**
     * @dev Number of epochs per day
     */
    uint256 internal constant _EPOCHS_PER_DAY = 225;

    /**
     * @dev Default "PUFFER_MODULE_0" module
     */
    bytes32 internal constant _PUFFER_MODULE_0 = bytes32("PUFFER_MODULE_0");

    /**
     * @inheritdoc IPufferProtocol
     */
    IGuardianModule public immutable override GUARDIAN_MODULE;

    /**
     * @inheritdoc IPufferProtocol
     */
    ValidatorTicket public immutable override VALIDATOR_TICKET;

    /**
     * @inheritdoc IPufferProtocol
     */
    PufferVaultV5 public immutable override PUFFER_VAULT;

    /**
     * @inheritdoc IPufferProtocol
     */
    PufferModuleManager public immutable PUFFER_MODULE_MANAGER;

    /**
     * @inheritdoc IPufferProtocol
     */
    IPufferOracleV2 public immutable override PUFFER_ORACLE;

    /**
     * @inheritdoc IPufferProtocol
     */
    IBeaconDepositContract public immutable override BEACON_DEPOSIT_CONTRACT;

    /**
     * @inheritdoc IPufferProtocol
     */
    address payable public immutable PUFFER_REVENUE_DISTRIBUTOR;

    constructor(
        PufferVaultV5 pufferVault,
        IGuardianModule guardianModule,
        address moduleManager,
        ValidatorTicket validatorTicket,
        IPufferOracleV2 oracle,
        address beaconDepositContract,
        address payable pufferRevenueDistributor
    ) {
        GUARDIAN_MODULE = guardianModule;
        PUFFER_VAULT = PufferVaultV5(payable(address(pufferVault)));
        PUFFER_MODULE_MANAGER = PufferModuleManager(payable(moduleManager));
        VALIDATOR_TICKET = validatorTicket;
        PUFFER_ORACLE = oracle;
        BEACON_DEPOSIT_CONTRACT = IBeaconDepositContract(beaconDepositContract);
        PUFFER_REVENUE_DISTRIBUTOR = pufferRevenueDistributor;
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     */
    function initialize(address accessManager) external initializer {
        if (address(accessManager) == address(0)) {
            revert InvalidAddress();
        }
        __AccessManaged_init(accessManager);
        _createPufferModule(_PUFFER_MODULE_0);
        _changeMinimumVTAmount(30 * _EPOCHS_PER_DAY); // 30 days worth of ETH is the minimum VT amount
        _setVTPenalty(10 * _EPOCHS_PER_DAY); // 10 days worth of ETH is the VT penalty
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
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
        _callPermit(address(VALIDATOR_TICKET), permit);

        // slither-disable-next-line unchecked-transfer
        VALIDATOR_TICKET.transferFrom(msg.sender, address(this), permit.amount);

        ProtocolStorage storage $ = _getPufferProtocolStorage();
        $.nodeOperatorInfo[node].deprecated_vtBalance += SafeCast.toUint96(permit.amount);
        emit ValidatorTicketsDeposited(node, msg.sender, permit.amount);
    }

    /**
     * @notice New function that allows anybody to deposit ETH for a node operator (use this instead of `depositValidatorTickets`)
     * This ETH is used as a VT payment.
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function depositValidationTime(address node, uint256 vtConsumptionAmount, bytes[] calldata vtConsumptionSignature)
        external
        payable
        restricted
    {
        require(node != address(0), InvalidAddress());
        require(msg.value > 0, InvalidETHAmount());

        ProtocolStorage storage $ = _getPufferProtocolStorage();

        _settleVTAccounting({
            $: $,
            node: node,
            totalEpochsValidated: vtConsumptionAmount,
            vtConsumptionSignature: vtConsumptionSignature,
            deprecated_burntVTs: 0
        });

        $.nodeOperatorInfo[node].validationTime += SafeCast.toUint96(msg.value);
        emit ValidationTimeDeposited({ node: node, ethAmount: msg.value });
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
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
        VALIDATOR_TICKET.transfer(recipient, amount);

        emit ValidatorTicketsWithdrawn(msg.sender, recipient, amount);
    }

    /**
     * @notice New function that allows the transaction sender (node operator) to withdraw WETH to a recipient (use this instead of `withdrawValidatorTickets`)
     * The Validation time can be withdrawn if there are no active or pending validators
     * The WETH is sent to the recipient
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
        address weth = PUFFER_VAULT.asset();
        weth.call{ value: amount }("");
        // Transfer WETH to the recipient
        ERC20(weth).transfer(recipient, amount);

        emit ValidationTimeWithdrawn(msg.sender, recipient, amount);
    }

    /**
     * @notice Registers a validator key and consumes the ETH for the validation time for the other active validators.
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function registerValidatorKey(
        ValidatorKeyData calldata data,
        bytes32 moduleName,
        uint256 totalEpochsValidated,
        bytes[] calldata vtConsumptionSignature
    ) external payable restricted {
        ProtocolStorage storage $ = _getPufferProtocolStorage();

        _checkValidatorRegistrationInputs({ $: $, data: data, moduleName: moduleName });

        uint256 epochCurrentPrice = PUFFER_ORACLE.getValidatorTicketPrice();

        // The node operator must deposit 1.5 ETH or more + minimum validation time for ~30 days
        // At the moment thats roughly 30 days * 225 (there is rougly 225 epochs per day)
        uint256 minimumETHRequired = _VALIDATOR_BOND + (_MINIMUM_EPOCHS_VALIDATION * epochCurrentPrice);

        emit ValidationTimeDeposited({ node: msg.sender, ethAmount: (msg.value - _VALIDATOR_BOND) });

        require(msg.value >= minimumETHRequired, InvalidETHAmount());

        _settleVTAccounting({
            $: $,
            node: msg.sender,
            totalEpochsValidated: totalEpochsValidated,
            vtConsumptionSignature: vtConsumptionSignature,
            deprecated_burntVTs: 0
        });

        // The bond is converted to pufETH at the current exchange rate
        uint256 pufETHBondAmount = PUFFER_VAULT.depositETH{ value: _VALIDATOR_BOND }(address(this));

        uint256 pufferModuleIndex = $.pendingValidatorIndices[moduleName];

        // No need for SafeCast
        $.validators[moduleName][pufferModuleIndex] = Validator({
            pubKey: data.blsPubKey,
            status: Status.PENDING,
            module: address($.modules[moduleName]),
            bond: uint96(pufETHBondAmount),
            node: msg.sender
        });

        // Increment indices for this module and number of validators registered
        unchecked {
            $.nodeOperatorInfo[msg.sender].epochPrice = epochCurrentPrice;
            $.nodeOperatorInfo[msg.sender].validationTime += (msg.value - _VALIDATOR_BOND);
            ++$.nodeOperatorInfo[msg.sender].pendingValidatorCount;
            ++$.pendingValidatorIndices[moduleName];
            ++$.moduleLimits[moduleName].numberOfRegisteredValidators;
        }

        emit NumberOfRegisteredValidatorsChanged(moduleName, $.moduleLimits[moduleName].numberOfRegisteredValidators);
        emit ValidatorKeyRegistered(data.blsPubKey, pufferModuleIndex, moduleName);
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted to Puffer Paymaster
     */
    function provisionNode(bytes calldata validatorSignature, bytes32 depositRootHash) external restricted {
        if (depositRootHash != BEACON_DEPOSIT_CONTRACT.get_deposit_root()) {
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

        // Mark the validator as active
        $.validators[moduleName][index].status = Status.ACTIVE;
    }

    function _batchHandleWithdrawalsAccounting(
        Withdrawals[] memory bondWithdrawals,
        StoppedValidatorInfo[] calldata validatorInfos
    ) internal {
        // In this loop, we transfer back the bonds, and do the accounting that affects the exchange rate
        for (uint256 i = 0; i < validatorInfos.length; ++i) {
            // If the withdrawal amount is bigger than 32 ETH, we cap it to 32 ETH
            // The excess is the rewards amount for that Node Operator
            uint256 transferAmount =
                validatorInfos[i].withdrawalAmount > 32 ether ? 32 ether : validatorInfos[i].withdrawalAmount;
            //solhint-disable-next-line avoid-low-level-calls
            (bool success,) =
                PufferModule(payable(validatorInfos[i].module)).call(address(PUFFER_VAULT), transferAmount, "");
            if (!success) {
                revert Failed();
            }

            // Skip the empty transfer (validator got slashed)
            if (bondWithdrawals[i].pufETHAmount == 0) {
                continue;
            }
            // slither-disable-next-line unchecked-transfer
            PUFFER_VAULT.transfer(bondWithdrawals[i].node, bondWithdrawals[i].pufETHAmount);
        }
        // slither-disable-start calls-loop
    }

    /**
     * @inheritdoc IPufferProtocol
     * @dev Restricted to Puffer Paymaster
     */
    function batchHandleWithdrawals(
        StoppedValidatorInfo[] calldata validatorInfos,
        bytes[] calldata guardianEOASignatures
    ) external restricted {
        GUARDIAN_MODULE.validateBatchWithdrawals(validatorInfos, guardianEOASignatures);

        ProtocolStorage storage $ = _getPufferProtocolStorage();

        BurnAmounts memory burnAmounts;
        Withdrawals[] memory bondWithdrawals = new Withdrawals[](validatorInfos.length);

        // We MUST NOT do the burning/oracle update/transferring ETH from the PufferModule -> PufferVault
        // because it affects pufETH exchange rate

        // First, we do the calculations
        // slither-disable-start calls-loop
        for (uint256 i = 0; i < validatorInfos.length; ++i) {
            Validator storage validator =
                $.validators[validatorInfos[i].moduleName][validatorInfos[i].pufferModuleIndex];

            if (validator.status != Status.ACTIVE) {
                revert InvalidValidatorState(validator.status);
            }

            // Save the Node address for the bond transfer
            bondWithdrawals[i].node = validator.node;

            uint96 bondAmount = validator.bond;
            // Get the burnAmount for the withdrawal at the current exchange rate
            uint256 burnAmount =
                _getBondBurnAmount({ validatorInfo: validatorInfos[i], validatorBondAmount: bondAmount });
            uint256 vtBurnAmount = _getVTBurnAmount($, validatorInfos[i]);

            // We need to scope the variables to avoid stack too deep errors
            {
                uint256 epochValidated = validatorInfos[i].totalEpochsValidated;
                bytes[] calldata vtConsumptionSignature = validatorInfos[i].vtConsumptionSignature;
                burnAmounts.vt +=
                    _useVTOrValidationTime($, validator, vtBurnAmount, epochValidated, vtConsumptionSignature);
            }

            // Update the burnAmounts
            burnAmounts.pufETH += burnAmount;

            // Store the withdrawal amount for that node operator
            // nosemgrep basic-arithmetic-underflow
            bondWithdrawals[i].pufETHAmount = (bondAmount - burnAmount);

            emit ValidatorExited({
                pubKey: validator.pubKey,
                pufferModuleIndex: validatorInfos[i].pufferModuleIndex,
                moduleName: validatorInfos[i].moduleName,
                pufETHBurnAmount: burnAmount,
                vtBurnAmount: vtBurnAmount
            });

            // Decrease the number of registered validators for that module
            _decreaseNumberOfRegisteredValidators($, validatorInfos[i].moduleName);
            // Storage VT and the active validator count update for the Node Operator
            // nosemgrep basic-arithmetic-underflow
            --$.nodeOperatorInfo[validator.node].activeValidatorCount;

            delete validator.node;
            delete validator.bond;
            delete validator.module;
            delete validator.status;
            delete validator.pubKey;
        }

        VALIDATOR_TICKET.burn(burnAmounts.vt);
        // Because we've calculated everything in the previous loop, we can do the burning
        PUFFER_VAULT.burn(burnAmounts.pufETH);
        // Deduct 32 ETH from the `lockedETHAmount` on the PufferOracle
        PUFFER_ORACLE.exitValidators(validatorInfos.length);

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
        GUARDIAN_MODULE.validateSkipProvisioning({
            moduleName: moduleName,
            skippedIndex: skippedIndex,
            guardianEOASignatures: guardianEOASignatures
        });

        uint256 vtPricePerEpoch = PUFFER_ORACLE.getValidatorTicketPrice();

        $.nodeOperatorInfo[node].validationTime -= ($.vtPenaltyEpochs * vtPricePerEpoch);
        --$.nodeOperatorInfo[node].pendingValidatorCount;

        // Change the status of that validator
        $.validators[moduleName][skippedIndex].status = Status.SKIPPED;

        // Transfer pufETH to that node operator
        // slither-disable-next-line unchecked-transfer
        PUFFER_VAULT.transfer(node, $.validators[moduleName][skippedIndex].bond);

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
        PufferModule module = PUFFER_MODULE_MANAGER.createNewPufferModule(moduleName);
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
        // This acts as a validation if the module is existent
        // +1 is to validate the current transaction registration
        if (($.moduleLimits[moduleName].numberOfRegisteredValidators + 1) > $.moduleLimits[moduleName].allowedLimit) {
            revert ValidatorLimitForModuleReached();
        }

        if (data.blsPubKey.length != _BLS_PUB_KEY_LENGTH) {
            revert InvalidBLSPubKey();
        }
    }

    function _changeMinimumVTAmount(uint256 newMinimumVtAmount) internal {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        if (newMinimumVtAmount < $.vtPenaltyEpochs) {
            revert InvalidVTAmount();
        }
        emit MinimumVTAmountChanged($.minimumVtAmount, newMinimumVtAmount);
        $.minimumVtAmount = newMinimumVtAmount;
    }

    function _getBondBurnAmount(StoppedValidatorInfo calldata validatorInfo, uint256 validatorBondAmount)
        internal
        view
        returns (uint256 pufETHBurnAmount)
    {
        // Case 1:
        // The Validator was slashed, we burn the whole bond for that validator
        if (validatorInfo.wasSlashed) {
            return validatorBondAmount;
        }

        // Case 2:
        // The withdrawal amount is less than 32 ETH, we burn the difference to cover up the loss for inactivity
        if (validatorInfo.withdrawalAmount < 32 ether) {
            pufETHBurnAmount = PUFFER_VAULT.convertToSharesUp(32 ether - validatorInfo.withdrawalAmount);
        }
        // Case 3:
        // Withdrawal amount was >= 32 ether, we don't burn anything
        return pufETHBurnAmount;
    }

    function _validateSignaturesAndProvisionValidator(
        ProtocolStorage storage $,
        bytes32 moduleName,
        uint256 index,
        bytes calldata validatorSignature
    ) internal {
        bytes memory validatorPubKey = $.validators[moduleName][index].pubKey;

        bytes memory withdrawalCredentials = getWithdrawalCredentials($.validators[moduleName][index].module);

        bytes32 depositDataRoot =
            LibBeaconchainContract.getDepositDataRoot(validatorPubKey, validatorSignature, withdrawalCredentials);

        PufferModule module = $.modules[moduleName];

        // Transfer 32 ETH to the module
        PUFFER_VAULT.transferETH(address(module), 32 ether);

        emit SuccessfullyProvisioned(validatorPubKey, index, moduleName);

        // Increase lockedETH on Puffer Oracle
        PUFFER_ORACLE.provisionNode();

        module.callStake({ pubKey: validatorPubKey, signature: validatorSignature, depositDataRoot: depositDataRoot });
    }

    function _useVTOrValidationTime(
        ProtocolStorage storage $,
        Validator storage validator,
        uint256 vtBurnAmount,
        uint256 totalEpochsValidated,
        bytes[] calldata vtConsumptionSignature
    ) internal returns (uint256 burnedAmount) {
        // Burn the VT first, then fallback to ETH from the node operator
        uint256 nodeVTBalance = $.nodeOperatorInfo[validator.node].deprecated_vtBalance;

        // If the node operator has VT, we burn it first
        if (nodeVTBalance > 0) {
            if (nodeVTBalance >= vtBurnAmount) {
                // Burn the VT first, and update the node operator VT balance
                burnedAmount = vtBurnAmount;
                // nosemgrep basic-arithmetic-underflow
                $.nodeOperatorInfo[validator.node].deprecated_vtBalance -= SafeCast.toUint96(vtBurnAmount);

                return burnedAmount;
            }

            // If the node operator has less VT than the amount to burn, we burn all of it, and we use the validation time
            burnedAmount = nodeVTBalance;
            // nosemgrep basic-arithmetic-underflow
            $.nodeOperatorInfo[validator.node].deprecated_vtBalance -= SafeCast.toUint96(nodeVTBalance);

            _settleVTAccounting({
                $: $,
                node: validator.node,
                totalEpochsValidated: totalEpochsValidated,
                vtConsumptionSignature: vtConsumptionSignature,
                deprecated_burntVTs: nodeVTBalance
            });

            return burnedAmount;
        }

        // If the node operator has no VT, we use the validation time
        _settleVTAccounting({
            $: $,
            node: validator.node,
            totalEpochsValidated: totalEpochsValidated,
            vtConsumptionSignature: vtConsumptionSignature,
            deprecated_burntVTs: 0
        });
    }

    function _settleVTAccounting(
        ProtocolStorage storage $,
        address node,
        uint256 totalEpochsValidated,
        bytes[] calldata vtConsumptionSignature,
        uint256 deprecated_burntVTs
    ) internal {
        // There is nothing to settle if this is the first validator for the node operator
        if ($.nodeOperatorInfo[node].activeValidatorCount + $.nodeOperatorInfo[node].pendingValidatorCount == 0) {
            return;
        }

        // We have no way of getting the present consumed amount for the other validators on-chain, so we use Puffer Backend service to get that amount and a signature from the service
        bytes32 messageHash = keccak256(abi.encode(node, totalEpochsValidated, _useNonce(node)));

        GUARDIAN_MODULE.validateGuardiansEOASignatures({
            eoaSignatures: vtConsumptionSignature,
            signedMessageHash: messageHash
        });

        uint256 epochCurrentPrice = PUFFER_ORACLE.getValidatorTicketPrice();

        uint256 meanPrice = ($.nodeOperatorInfo[node].epochPrice + epochCurrentPrice) / 2;

        uint256 previousTotalEpochsValidated = $.nodeOperatorInfo[node].totalEpochsValidated;

        uint256 validatorTicketsBurnt = deprecated_burntVTs * 225 / 1 ether; // 1 VT = 1 DAY = 225 Epochs

        uint256 amountToConsume =
            (totalEpochsValidated - previousTotalEpochsValidated - validatorTicketsBurnt) * meanPrice;

        if (amountToConsume <= $.vtPenaltyEpochs * meanPrice) {
            amountToConsume = $.vtPenaltyEpochs * meanPrice;
        }

        // Update the current epoch VT price for the node operator
        $.nodeOperatorInfo[node].epochPrice = epochCurrentPrice;
        $.nodeOperatorInfo[node].totalEpochsValidated = totalEpochsValidated;
        $.nodeOperatorInfo[node].validationTime -= amountToConsume;

        address weth = PUFFER_VAULT.asset();

        // WETH is a contract that has a fallback function that accepts ETH, and never reverts
        weth.call{ value: amountToConsume }("");

        // Transfer WETH to the Revenue Distributor, it will be slow released to the PufferVault
        ERC20(weth).transfer(PUFFER_REVENUE_DISTRIBUTOR, amountToConsume);
    }

    function _getVTBurnAmount(ProtocolStorage storage $, StoppedValidatorInfo calldata validatorInfo)
        internal
        view
        returns (uint256)
    {
        uint256 validatedEpochs = validatorInfo.totalEpochsValidated;
        // Epoch has 32 blocks, each block is 12 seconds, we upscale to 18 decimals to get the VT amount and divide by 1 day
        // The formula is validatedEpochs * 32 * 12 * 1 ether / 1 days (4444444444444444.44444444...) we round it up
        uint256 vtBurnAmount = validatedEpochs * 4444444444444445;

        // Return the bigger of the two
        return vtBurnAmount > $.minimumVtAmount ? vtBurnAmount : $.minimumVtAmount;
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

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
