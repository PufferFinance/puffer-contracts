// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { PufferModuleManager } from "./PufferModuleManager.sol";
import { IPufferOracleV2 } from "./interface/IPufferOracleV2.sol";
import { IGuardianModule } from "./interface/IGuardianModule.sol";
import { IBeaconDepositContract } from "./interface/IBeaconDepositContract.sol";
import { Validator } from "./struct/Validator.sol";
import { Status } from "./struct/Status.sol";
import { WithdrawalType } from "./struct/WithdrawalType.sol";
import { ProtocolStorage, NodeInfo, ModuleLimit } from "./struct/ProtocolStorage.sol";
import { LibBeaconchainContract } from "./LibBeaconchainContract.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";
import { ValidatorTicket } from "./ValidatorTicket.sol";
import { Unauthorized, InvalidAddress } from "./Errors.sol";
import { StoppedValidatorInfo } from "./struct/StoppedValidatorInfo.sol";
import { PufferModule } from "./PufferModule.sol";
import { EpochsValidatedSignature } from "./struct/Signatures.sol";
import { PufferProtocolBase } from "./PufferProtocolBase.sol";
import { IPufferProtocolLogic } from "./interface/IPufferProtocolLogic.sol";

/**
 * @title PufferProtocol
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 * @dev Upgradeable smart contract for the Puffer Protocol
 * Storage variables are located in PufferProtocolStorage.sol
 */
contract PufferProtocol is IPufferProtocol, AccessManagedUpgradeable, UUPSUpgradeable, PufferProtocolBase {
    using MessageHashUtils for bytes32;

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
    {
        _disableInitializers();
    }

    receive() external payable { }

    /**
     * @notice Fallback function to delegatecall the Puffer Protocol Logic
     * @dev If a function selector is not found in this contract, it will delegatecall the Puffer Protocol Logic.
     *      This is done to be able to call functions from the Puffer Protocol Logic contract without having to
     *      declare them in this contract as well, manually forwarding them to the Puffer Protocol Logic contract.
     */
    fallback() external payable {
        (bool success, bytes memory returnData) = _getPufferProtocolStorage().pufferProtocolLogic.delegatecall(msg.data);

        if (success) {
            assembly {
                return(add(returnData, 0x20), mload(returnData))
            }
        } else {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }

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
    function depositValidatorTickets(address node, uint256 amount) external restricted {
        if (node == address(0)) {
            revert InvalidAddress();
        }

        // slither-disable-next-line unchecked-transfer
        _VALIDATOR_TICKET.transferFrom(msg.sender, address(this), amount);

        ProtocolStorage storage $ = _getPufferProtocolStorage();
        $.nodeOperatorInfo[node].deprecated_vtBalance += SafeCast.toUint96(amount);
        emit ValidatorTicketsDeposited(node, msg.sender, amount);
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

                // bytes32 messageHash = keccak256(abi.encode(msg.sender, pubkeys[i], gweiAmounts[i], _useNonce(IPufferProtocol.requestWithdrawal.selector, msg.sender), deadline)).toEthSignedMessageHash();
                bytes32 messageHash = keccak256(
                    abi.encode(
                        msg.sender,
                        pubkeys[i],
                        gweiAmounts[i],
                        _useNonce(IPufferProtocol.requestWithdrawal.selector, msg.sender),
                        deadline
                    )
                ).toEthSignedMessageHash();
                bool validSignatures =
                    _GUARDIAN_MODULE.validateGuardiansEOASignatures(validatorAmountsSignatures[i], messageHash);
                if (!validSignatures) {
                    revert Unauthorized();
                }
            }
        }

        _PUFFER_MODULE_MANAGER.requestWithdrawal{ value: msg.value }(moduleName, pubkeys, gweiAmounts);
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

    function _changeMinimumVTAmount(uint256 newMinimumVtAmount) internal {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        if (newMinimumVtAmount < $.vtPenaltyEpochs) {
            revert InvalidVTAmount();
        }
        emit MinimumVTAmountChanged($.minimumVtAmount, newMinimumVtAmount);
        $.minimumVtAmount = newMinimumVtAmount;
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

    function _setPufferProtocolLogic(address newPufferProtocolLogic) internal {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        emit PufferProtocolLogicSet($.pufferProtocolLogic, newPufferProtocolLogic);
        $.pufferProtocolLogic = newPufferProtocolLogic;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }

    function getPufferProtocolLogic() external view override returns (address) {
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
