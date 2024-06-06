// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Validator } from "../struct/Validator.sol";
import { ValidatorKeyData } from "../struct/ValidatorKeyData.sol";
import { IGuardianModule } from "../interface/IGuardianModule.sol";
import { IPufferModuleManager } from "../interface/IPufferModuleManager.sol";
import { PufferVaultV2 } from "../PufferVaultV2.sol";
import { IPufferOracleV2 } from "../interface/IPufferOracleV2.sol";
import { Status } from "../struct/Status.sol";
import { Permit } from "../structs/Permit.sol";
import { ValidatorTicket } from "../ValidatorTicket.sol";
import { NodeInfo } from "../struct/NodeInfo.sol";
import { ModuleLimit } from "../struct/ProtocolStorage.sol";
import { StoppedValidatorInfo } from "../struct/StoppedValidatorInfo.sol";
import { IBeaconDepositContract } from "../interface/IBeaconDepositContract.sol";

/**
 * @title IPufferProtocol
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufferProtocol {
    /**
     * @notice Thrown when the deposit state that is provided doesn't match the one on Beacon deposit contract
     */
    error InvalidDepositRootHash();

    /**
     * @notice Thrown when the number of BLS public key shares doesn't match guardians threshold number
     * @dev Signature "0x8cdea6a6"
     */
    error InvalidBLSPublicKeySet();

    /**
     * @notice Thrown when the node operator tries to withdraw VTs from the PufferProtocol but has active/pending validators
     * @dev Signature "0x22242546"
     */
    error ActiveOrPendingValidatorsExist();

    /**
     * @notice Thrown on the module creation if the module already exists
     * @dev Signature "0x2157f2d7"
     */
    error ModuleAlreadyExists();

    /**
     * @notice Thrown when the new validators tires to register to a module, but the validator limit for that module is already reached
     * @dev Signature "0xb75c5781"
     */
    error ValidatorLimitForModuleReached();

    /**
     * @notice Thrown when the number of BLS private key shares doesn't match guardians number
     * @dev Signature "0x2c8f9aa3"
     */
    error InvalidBLSPrivateKeyShares();

    /**
     * @notice Thrown when the BLS public key is not valid
     * @dev Signature "0x7eef7967"
     */
    error InvalidBLSPubKey();

    /**
     * @notice Thrown when validator is not in a valid state
     * @dev Signature "0x3001591c"
     */
    error InvalidValidatorState(Status status);

    /**
     * @notice Thrown if the sender did not send enough ETH in the transaction
     * @dev Signature "0x242b035c"
     */
    error InvalidETHAmount();

    /**
     * @notice Thrown if the sender tries to register validator with invalid VT amount
     * @dev Signature "0x95c01f62"
     */
    error InvalidVTAmount();

    /**
     * @notice Thrown if the ETH transfer from the PufferModule to the PufferVault fails
     * @dev Signature "0x625a40e6"
     */
    error Failed();

    /**
     * @notice Emitted when the number of active validators changes
     * @dev Signature "0xc06afc2b3c88873a9be580de9bbbcc7fea3027ef0c25fd75d5411ed3195abcec"
     */
    event NumberOfRegisteredValidatorsChanged(bytes32 indexed moduleName, uint256 newNumberOfRegisteredValidators);

    /**
     * @notice Emitted when the new Puffer module is created
     * @dev Signature "0x8ad2a9260a8e9a01d1ccd66b3875bcbdf8c4d0c552bc51a7d2125d4146e1d2d6"
     */
    event NewPufferModuleCreated(address module, bytes32 indexed moduleName, bytes32 withdrawalCredentials);

    /**
     * @notice Emitted when the module's validator limit is changed from `oldLimit` to `newLimit`
     * @dev Signature "0x21e92cbdc47ef718b9c77ea6a6ee50ff4dd6362ee22041ab77a46dacb93f5355"
     */
    event ValidatorLimitPerModuleChanged(uint256 oldLimit, uint256 newLimit);

    /**
     * @notice Emitted when the minimum number of days for ValidatorTickets is changed from `oldMinimumNumberOfDays` to `newMinimumNumberOfDays`
     * @dev Signature "0xc6f97db308054b44394df54aa17699adff6b9996e9cffb4dcbcb127e20b68abc"
     */
    event MinimumVTAmountChanged(uint256 oldMinimumNumberOfDays, uint256 newMinimumNumberOfDays);

    /**
     * @notice Emitted when the VT Penalty amount is changed from `oldPenalty` to `newPenalty`
     * @dev Signature "0xfceca97b5d1d1164f9a15e42f38eaf4a6e760d8505f06161a258d4bf21cc4ee7"
     */
    event VTPenaltyChanged(uint256 oldPenalty, uint256 newPenalty);

    /**
     * @notice Emitted when VT is deposited to the protocol
     * @dev Signature "0xd47eb90c0b945baf5f3ae3f1384a7a524a6f78f1461b354c4a09c4001a5cee9c"
     */
    event ValidatorTicketsDeposited(address indexed node, address indexed depositor, uint256 amount);

    /**
     * @notice Emitted when VT is withdrawn from the protocol
     * @dev Signature "0xdf7e884ecac11650e1285647b057fa733a7bb9f1da100e7a8c22aafe4bdf6f40"
     */
    event ValidatorTicketsWithdrawn(address indexed node, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when the guardians decide to skip validator provisioning for `moduleName`
     * @dev Signature "0x088dc5dc64f3e8df8da5140a284d3018a717d6b009e605513bb28a2b466d38ee"
     */
    event ValidatorSkipped(bytes pubKey, uint256 indexed pufferModuleIndex, bytes32 indexed moduleName);

    /**
     * @notice Emitted when the module weights changes from `oldWeights` to `newWeights`
     * @dev Signature "0xd4c9924bd67ff5bd900dc6b1e03b839c6ffa35386096b0c2a17c03638fa4ebff"
     */
    event ModuleWeightsChanged(bytes32[] oldWeights, bytes32[] newWeights);

    /**
     * @notice Emitted when the Validator key is registered
     * @param pubKey is the validator public key
     * @param pufferModuleIndex is the internal validator index in Puffer Finance, not to be mistaken with validator index on Beacon Chain
     * @param moduleName is the staking Module
     * @param usingEnclave is indicating if the validator is using secure enclave
     * @dev Signature "0xc73344cf227e056eee8d82aee54078c9b55323b61d17f61587eb570873f8e319"
     */
    event ValidatorKeyRegistered(
        bytes pubKey, uint256 indexed pufferModuleIndex, bytes32 indexed moduleName, bool usingEnclave
    );

    /**
     * @notice Emitted when the Validator exited and stopped validating
     * @param pubKey is the validator public key
     * @param pufferModuleIndex is the internal validator index in Puffer Finance, not to be mistaken with validator index on Beacon Chain
     * @param moduleName is the staking Module
     * @param pufETHBurnAmount The amount of pufETH burned from the Node Operator
     * @dev Signature "0xf435da9e3aeccc40d39fece7829f9941965ceee00d31fa7a89d608a273ea906e"
     */
    event ValidatorExited(
        bytes pubKey,
        uint256 indexed pufferModuleIndex,
        bytes32 indexed moduleName,
        uint256 pufETHBurnAmount,
        uint256 vtBurnAmount
    );

    /**
     * @notice Emitted when the Validator is provisioned
     * @param pubKey is the validator public key
     * @param pufferModuleIndex is the internal validator index in Puffer Finance, not to be mistaken with validator index on Beacon Chain
     * @param moduleName is the staking Module
     * @dev Signature "0x96cbbd073e24b0a7d0cab7dc347c239e52be23c1b44ce240b3b929821fed19a4"
     */
    event SuccessfullyProvisioned(bytes pubKey, uint256 indexed pufferModuleIndex, bytes32 indexed moduleName);

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
     */
    function depositValidatorTickets(Permit calldata permit, address node) external;

    /**
     * @notice Withdraws the `amount` of Validator Tickers from the `msg.sender` to the `recipient`
     * @dev Each active validator requires node operator to have at least `minimumVtAmount` locked
     */
    function withdrawValidatorTickets(uint96 amount, address recipient) external;

    /**
     * @notice Batch settling of validator withdrawals
     *
     * @notice Settles a validator withdrawal
     * @dev This is one of the most important methods in the protocol
     * It has multiple tasks:
     * 1. Burn the pufETH from the node operator (if the withdrawal amount was lower than 32 ETH)
     * 2. Burn the Validator Tickets from the node operator
     * 3. Transfer withdrawal ETH from the PufferModule of the Validator to the PufferVault
     * 4. Decrement the `lockedETHAmount` on the PufferOracle to reflect the new amount of locked ETH
     */
    function batchHandleWithdrawals(
        StoppedValidatorInfo[] calldata validatorInfos,
        bytes[] calldata guardianEOASignatures
    ) external;

    /**
     * @notice Skips the next validator for `moduleName`
     * @dev Restricted to Guardians
     */
    function skipProvisioning(bytes32 moduleName, bytes[] calldata guardianEOASignatures) external;

    /**
     * @notice Sets the module weights array to `newModuleWeights`
     * @dev Restricted to the DAO
     */
    function setModuleWeights(bytes32[] calldata newModuleWeights) external;

    /**
     * @notice Sets the module limits for `moduleName` to `limit`
     * @dev Restricted to the DAO
     */
    function setValidatorLimitPerModule(bytes32 moduleName, uint128 limit) external;

    /**
     * @notice Sets the Validator Ticket penalty amount to `newPenaltyAmount`
     * @dev Restricted to the DAO
     */
    function setVTPenalty(uint256 newPenaltyAmount) external;

    /**
     * @notice Changes the minimum number amount of VT that must be locked per validator
     * @dev Restricted to the DAO
     */
    function changeMinimumVTAmount(uint256 newMinimumVTAmount) external;

    /**
     * @notice Returns the guardian module
     */
    function GUARDIAN_MODULE() external view returns (IGuardianModule);

    /**
     * @notice Returns the Validator ticket ERC20 token
     */
    function VALIDATOR_TICKET() external view returns (ValidatorTicket);

    /**
     * @notice Returns the Puffer Vault
     */
    function PUFFER_VAULT() external view returns (PufferVaultV2);

    /**
     * @notice Returns the Puffer Module Manager
     */
    function PUFFER_MODULE_MANAGER() external view returns (IPufferModuleManager);

    /**
     * @notice Returns the Puffer Oracle
     */
    function PUFFER_ORACLE() external view returns (IPufferOracleV2);

    /**
     * @notice Returns Beacon Deposit Contract
     */
    function BEACON_DEPOSIT_CONTRACT() external view returns (IBeaconDepositContract);

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
     * @notice Provisions the next node that is in line for provisioning if the `guardianEnclaveSignatures` are valid
     * @dev You can check who is next for provisioning by calling `getNextValidatorToProvision` method
     */
    function provisionNode(
        bytes[] calldata guardianEnclaveSignatures,
        bytes calldata validatorSignature,
        bytes32 depositRootHash
    ) external;

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
     * @notice Registers a new validator key in a `moduleName` queue with a permit
     * @dev There is a queue per moduleName and it is FIFO
     *
     * If you are depositing without the permit, make sure to .approve pufETH to PufferProtocol
     * and populate permit.amount with the correct amount
     *
     * @param data The validator key data
     * @param moduleName The name of the module
     * @param pufETHPermit The permit for the pufETH
     * @param vtPermit The permit for the ValidatorTicket
     */
    function registerValidatorKey(
        ValidatorKeyData calldata data,
        bytes32 moduleName,
        Permit calldata pufETHPermit,
        Permit calldata vtPermit
    ) external payable;

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
     * @notice Returns the minimum amount of Validator Tokens to run a validator
     */
    function getMinimumVtAmount() external view returns (uint256);

    /**
     * @notice Reverts if the system is paused
     */
    function revertIfPaused() external;
}
