// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Validator } from "../struct/Validator.sol";
import { ValidatorKeyData } from "../struct/ValidatorKeyData.sol";
import { IGuardianModule } from "../interface/IGuardianModule.sol";
import { PufferModuleManager } from "../PufferModuleManager.sol";
import { PufferVaultV5 } from "../PufferVaultV5.sol";
import { IPufferOracleV2 } from "../interface/IPufferOracleV2.sol";
import { Status } from "../struct/Status.sol";
import { WithdrawalType } from "../struct/WithdrawalType.sol";
import { Permit } from "../structs/Permit.sol";
import { ValidatorTicket } from "../ValidatorTicket.sol";
import { NodeInfo } from "../struct/NodeInfo.sol";
import { ModuleLimit } from "../struct/ProtocolStorage.sol";
import { StoppedValidatorInfo } from "../struct/StoppedValidatorInfo.sol";
import { EpochsValidatedSignature } from "../struct/Signatures.sol";
import { IBeaconDepositContract } from "../interface/IBeaconDepositContract.sol";

/**
 * @title IPufferProtocol
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufferProtocol {

    /**
     * @notice Returns validator information
     * @param moduleName is the staking Module
     * @param pufferModuleIndex is the Index of the validator in Puffer, not to be mistaken with Validator index on beacon chain
     * @return Validator info struct
     */
    function getValidatorInfo(bytes32 moduleName, uint256 pufferModuleIndex) external view returns (Validator memory);

    /**
     * @notice Returns Penalty for submitting a bad validator registration
     * @dev If the guardians skip a validator, the node operator will be penalized
     * @return Number of epochs to burn for a penalty if a validator is skipped. epochs * vtPricePerEpoch = penalty in ETH
     * /// todo write any possible reasons for skipping a validator, here and in skipValidator method
     */
    function getVTPenalty() external view returns (uint256);

    /**
     * @notice Returns the node operator information
     * @param node is the node operator address
     * @return NodeInfo struct
     */
    function getNodeInfo(address node) external view returns (NodeInfo memory);

    /**
     * @notice Deposits Validator Tickets for the `node`
     * DEPRECATED - This method is deprecated and will be removed in the future upgrade
     */
    function depositValidatorTickets(address node, uint256 vtAmount) external;

    /**
     * @notice Withdraws the `amount` of Validator Tickers from the `msg.sender` to the `recipient`
     * DEPRECATED - This method is deprecated and will be removed in the future upgrade
     * @dev Each active validator requires node operator to have at least `minimumVtAmount` locked
     */
    function withdrawValidatorTickets(uint96 amount, address recipient) external;

    /**
     * @notice Requests a withdrawal for the given validators. This withdrawal can be total or partial.
     *         If the amount is 0, the withdrawal is total and the validator will be fully exited.
     *         If it is a partial withdrawal, the validator should not be below 32 ETH or the request will be ignored.
     * @param moduleName The name of the module
     * @param indices The indices of the validators to withdraw
     * @param gweiAmounts The amounts of the validators to withdraw, in Gwei
     * @param withdrawalType The type of withdrawal
     * @param validatorAmountsSignatures The signatures of the guardians to validate the amount of the validators to withdraw
     * @param deadline The deadline for the signatures
     * @dev The pubkeys should be active validators on the same module
     * @dev There are 3 types of withdrawal:
     *      EXIT_VALIDATOR: The validator is fully exited. The gweiAmount needs to be 0
     *      DOWNSIZE: The number of batches of the validator is reduced. The gweiAmount needs to be exactly a multiple of a batch size (32 ETH in gwei)
     *              And the validator should have more than the requested number of batches
     *      WITHDRAW_REWARDS: The amount cannot be higher than what the protocol provisioned for the validator and must be validated by the guardians via the `validatorAmountsSignatures`
     * @dev The validatorAmountsSignatures is only needed when the withdrawal type is DOWNSIZE orWITHDRAW_REWARDS
     * @dev According to EIP-7002 there is a fee for each validator withdrawal request (See https://eips.ethereum.org/assets/eip-7002/fee_analysis)
     *      The fee is paid in the msg.value of this function. Since the fee is not fixed and might change, the excess amount will be kept in the PufferModule
     */
    function requestWithdrawal(
        bytes32 moduleName,
        uint256[] calldata indices,
        uint64[] calldata gweiAmounts,
        WithdrawalType[] calldata withdrawalType,
        bytes[][] calldata validatorAmountsSignatures,
        uint256 deadline
    ) external payable;


    /**
     * @notice Returns the guardian module
     */
    function GUARDIAN_MODULE() external view returns (IGuardianModule);

    /**
     * @notice Returns the Validator ticket ERC20 token
     * DEPRECATED - This method is deprecated and will be removed in the future upgrade
     */
    function VALIDATOR_TICKET() external view returns (ValidatorTicket);

    /**
     * @notice Returns the Puffer Vault
     */
    function PUFFER_VAULT() external view returns (PufferVaultV5);

    /**
     * @notice Returns the Puffer Module Manager
     */
    function PUFFER_MODULE_MANAGER() external view returns (PufferModuleManager);

    /**
     * @notice Returns the Puffer Oracle
     */
    function PUFFER_ORACLE() external view returns (IPufferOracleV2);

    /**
     * @notice Returns Beacon Deposit Contract
     */
    function BEACON_DEPOSIT_CONTRACT() external view returns (IBeaconDepositContract);

    /**
     * @notice Returns the Puffer Revenue Distributor
     */
    function PUFFER_REVENUE_DISTRIBUTOR() external view returns (address payable);

    /**
     * @notice Returns the current module weights
     */
    function getModuleWeights() external view returns (bytes32[] memory);

    /**
     * @notice Returns the module select index
     */
    function getModuleSelectIndex() external view returns (uint256);

    /**
     * @notice Returns the address for `moduleName`
     */
    function getModuleAddress(bytes32 moduleName) external view returns (address);

    /**
     * @notice Provisions the next node that is in line for provisioning
     * @param validatorSignature The signature of the validator to provision
     * @param depositRootHash The deposit root hash of the validator
     * @dev You can check who is next for provisioning by calling `getNextValidatorToProvision` method
     */
    function provisionNode(bytes calldata validatorSignature, bytes32 depositRootHash) external;

    /**
     * @notice Returns the deposit_data_root
     * @param pubKey is the public key of the validator
     * @param signature is the validator's signature over deposit data
     * @param withdrawalCredentials is the withdrawal credentials (one of Puffer Modules)
     * @return deposit_data_root
     */
    function getDepositDataRoot(bytes calldata pubKey, bytes calldata signature, bytes calldata withdrawalCredentials)
        external
        pure
        returns (bytes32);

    /**
     * @notice Returns the array of Puffer validators
     * @dev This is meant for OFF-CHAIN use, as it can be very expensive to call
     */
    function getValidators(bytes32 moduleName) external view returns (Validator[] memory);

    /**
     * @notice Returns the number of active validators for `moduleName`
     */
    function getModuleLimitInformation(bytes32 moduleName) external view returns (ModuleLimit memory info);

    /**
     * @notice Creates a new Puffer module with `moduleName`
     * @param moduleName The name of the module
     * @dev It will revert if you try to create two modules with the same name
     * @return The address of the new module
     */
    function createPufferModule(bytes32 moduleName) external returns (address);


    /**
     * @notice Returns the pending validator index for `moduleName`
     */
    function getPendingValidatorIndex(bytes32 moduleName) external view returns (uint256);

    /**
     * @notice Returns the next validator index for provisioning for `moduleName`
     */
    function getNextValidatorToBeProvisionedIndex(bytes32 moduleName) external view returns (uint256);

    /**
     * @notice Returns the amount of Validator Tickets locked in the PufferProtocol for the `owner`
     * The real VT balance may be different from the balance in the PufferProtocol
     * When the Validator is exited, the VTs are burned and the balance is decreased
     * DEPRECATED - This method is deprecated and will be removed in the future upgrade
     */
    function getValidatorTicketsBalance(address owner) external returns (uint256);

    /**
     * @notice Returns the next in line for provisioning
     * @dev The order in which the modules are selected is based on Module Weights
     * Every module has its own FIFO queue for provisioning
     */
    function getNextValidatorToProvision() external view returns (bytes32 moduleName, uint256 indexToBeProvisioned);

    /**
     * @notice Returns the withdrawal credentials for a `module`
     */
    function getWithdrawalCredentials(address module) external view returns (bytes memory);

    /**
     * @notice Returns the minimum amount of Epochs a validator needs to run
     */
    function getMinimumVtAmount() external view returns (uint256);

    /**
     * @notice Reverts if the system is paused
     */
    function revertIfPaused() external;
}
