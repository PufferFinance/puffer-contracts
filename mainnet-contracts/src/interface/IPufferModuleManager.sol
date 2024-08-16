// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferModule } from "../interface/IPufferModule.sol";
import { IRestakingOperator } from "../interface/IRestakingOperator.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";
import { BeaconChainProofs } from "eigenlayer/libraries/BeaconChainProofs.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRegistryCoordinator, IBLSApkRegistry } from "eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";

/**
 * @title IPufferModuleManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufferModuleManager {
    /**
     * @notice Thrown if the module name is not allowed
     */
    error ForbiddenModuleName();

    /**
     * @notice Emitted when the Custom Call from the restakingOperator is successful
     * @dev Signature "0x80b240e4b7a31d61bdee28b97592a7c0ad486cb27d11ee5c6b90530db4e949ff"
     */
    event CustomCallSucceeded(address indexed restakingOperator, address target, bytes customCalldata, bytes response);

    /**
     * @notice Emitted when a Restaking Operator is opted into a slasher
     * @param restakingOperator is the address of the restaking operator
     * @param slasher is the address of the slasher contract
     * @dev Signature "0xfaf85fa92e9a913f582def722d9da998852ef6cd2fc7715266e3c3b16495c7ac"
     */
    event RestakingOperatorOptedInSlasher(address indexed restakingOperator, address indexed slasher);

    /**
     * @notice Emitted when the Restaking Operator is created
     * @param restakingOperator is the address of the restaking operator
     * @param operatorDetails is the struct with new operator details
     * @dev Signature "0xbb6c366230e589c402e164f680d07db88a6c1d4dda4dd2dcbab5528c09a6b046"
     */
    event RestakingOperatorCreated(
        address indexed restakingOperator, IDelegationManager.OperatorDetails operatorDetails
    );

    /**
     * @notice Emitted when the Restaking Operator is modified
     * @param restakingOperator is the address of the restaking operator
     * @param newOperatorDetails is the struct with new operator details
     * @dev Signature "0xee78237d6444cc6c9083c1ef31a82b0feac23fbdf0cf52d7b0ed66dfa5f7f9f2"
     */
    event RestakingOperatorModified(
        address indexed restakingOperator, IDelegationManager.OperatorDetails newOperatorDetails
    );

    /**
     * @notice Emitted when the Withdrawals are queued
     * @param moduleName is the name of the module
     * @param shareAmount is the amount of shares
     * @dev Signature "0xfa1bd67700189b28b5a9085170838266813878ca3237b31a33358644a22a2f0e"
     */
    event WithdrawalsQueued(bytes32 indexed moduleName, uint256 shareAmount, bytes32 withdrawalRoot);

    /**
     * @notice Emitted when the Restaking Operator is updated with a new metadata URI
     * @param restakingOperator is the address of the restaking operator
     * @param metadataURI is the new URI of the operator's metadata
     * @dev Signature "0x4cb1b839d29c7a6f051ae51c7b439f2f8f991de54a4b5906503a06a0892ba2c4"
     */
    event RestakingOperatorMetadataURIUpdated(address indexed restakingOperator, string metadataURI);

    /**
     * @notice Emitted when the Puffer Module is delegated
     * @param moduleName the module name to be delegated
     * @param operator the operator to delegate to
     * @dev Signature "0xfa610363b3f4985bba03612919e946ac0bccf11c8e067255de41e530f8cc0997"
     */
    event PufferModuleDelegated(bytes32 indexed moduleName, address operator);

    /**
     * @notice Emitted when the Puffer Module is undelegated
     * @param moduleName the module name to be undelegated
     * @dev Signature "0x4651591b511cac27601595cefbb19b2f0a04ec7b9348230f44a1309b9d70a8c9"
     */
    event PufferModuleUndelegated(bytes32 indexed moduleName);

    /**
     * @notice Emitted when the restaking operator avs signature proof is updated
     * @param restakingOperator is the address of the restaking operator
     * @param digestHash is the message hash
     * @param signer is the address of the signature signer
     * @dev Signature "0x3a6a179c72e503b78f992c3aa1a8d451c366c446c086cee5a811a3d03445a62f"
     */
    event AVSRegistrationSignatureProofUpdated(address indexed restakingOperator, bytes32 digestHash, address signer);

    /**
     * @notice Emitted when a Node Operator verifies withdrawal credentials
     * @param moduleName is the name of the module
     * @param validatorIndices is the indices of the validators
     * @dev Signature "0x6722c9fd02a30e38d993af1ef931e54d0c24d0eae5eba68982773ce120b8ddee"
     */
    event ValidatorCredentialsVerified(bytes32 indexed moduleName, uint40[] validatorIndices);

    /**
     * @notice Emitted when the withdrawals are completed
     * @param moduleName is the name of the module
     * @param sharesWithdrawn is the shares withdrawn
     * @dev Signature "0x46ca5934f7ca805e7fbdc05e90e3ecbea495c41e35ba48e24f053c0c3d25af1e"
     */
    event CompletedQueuedWithdrawals(bytes32 indexed moduleName, uint256 sharesWithdrawn);

    /**
     * @notice Emitted when the proof submitter is set for a Puffer Module
     * @param moduleName is the name of the module
     * @param proofSubmitter is the address of the proof submitter
     * @dev Signature "0x7f89a4fee8344b6c81af28f87562de8054623bc99874a118c25adad8f83bc7ae"
     */
    event ProofSubmitterSet(bytes32 indexed moduleName, address indexed proofSubmitter);

    /**
     * @notice Emitted when the Restaking Operator is registered to an AVS
     * @param restakingOperator is the address of the restaking operator
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param socket is the socket of the operator (typically an IP address)
     * @dev Signature "0x4651591b511cac27601595cefbb19b2f0a04ec7b9348230f44a1309b9d70a8c9"
     */
    event RestakingOperatorRegisteredToAVS(
        IRestakingOperator restakingOperator, address avsRegistryCoordinator, bytes quorumNumbers, string socket
    );

    /**
     * @notice Emitted when the Restaking Operator is registered to an AVS
     * @param restakingOperator is the address of the restaking operator
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param socket is the socket of the operator (typically an IP address)
     * @param operatorKickParams used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums
     * @dev Signature "0x4651591b511cac27601595cefbb19b2f0a04ec7b9348230f44a1309b9d70a8c9"
     */
    event RestakingOperatorRegisteredToAVSWithChurn(
        IRestakingOperator restakingOperator,
        address avsRegistryCoordinator,
        bytes quorumNumbers,
        string socket,
        IRegistryCoordinator.OperatorKickParam[] operatorKickParams
    );

    /**
     * @notice Emitted when the Restaking Operator is deregistered from an AVS
     * @param restakingOperator is the address of the restaking operator
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being deregistered from
     * @dev Signature "0x4651591b511cac27601595cefbb19b2f0a04ec7b9348230f44a1309b9d70a8c9"
     */
    event RestakingOperatorDeregisteredFromAVS(
        IRestakingOperator restakingOperator, address avsRegistryCoordinator, bytes quorumNumbers
    );

    /**
     * @notice Emitted when the Restaking Operator AVS Socket is updated
     * @param restakingOperator is the address of the restaking operator
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param socket is the new socket of the operator
     * @dev Signature "0x4651591b511cac27601595cefbb19b2f0a04ec7b9348230f44a1309b9d70a8c9"
     */
    event RestakingOperatorAVSSocketUpdated(
        IRestakingOperator restakingOperator, address avsRegistryCoordinator, string socket
    );

    /**
     * @notice Emitted when the Restaking Operator or PufferModule sets the calimer to `claimer`
     * @dev Signature "0x4925eafc82d0c4d67889898eeed64b18488ab19811e61620f387026dec126a28"
     */
    event ClaimerSet(address indexed rewardsReceiver, address indexed claimer);

    /**
     * @notice Returns the Puffer Module beacon address
     */
    function PUFFER_MODULE_BEACON() external view returns (address);

    /**
     * @notice Returns the Restaking Operator beacon address
     */
    function RESTAKING_OPERATOR_BEACON() external view returns (address);

    /**
     * @notice Returns the Puffer Protocol address
     */
    function PUFFER_PROTOCOL() external view returns (address);

    /**
     * @notice Returns the Puffer Vault address
     */
    function PUFFER_VAULT() external view returns (address payable);

    /**
     * @notice Create a new Restaking Operator
     * @param metadataURI is a URI for the operator's metadata, i.e. a link providing more details on the operator.
     *
     * @param delegationApprover Address to verify signatures when a staker wishes to delegate to the operator, as well as controlling "forced undelegations".
     *
     * @dev See IDelegationManager(EigenLayer) for more details about the other parameters
     * @dev Signature verification follows these rules:
     * 1) If this address is left as address(0), then any staker will be free to delegate to the operator, i.e. no signature verification will be performed.
     * 2) If this address is an EOA (i.e. it has no code), then we follow standard ECDSA signature verification for delegations to the operator.
     * 3) If this address is a contract (i.e. it has code) then we forward a call to the contract and verify that it returns the correct EIP-1271 "magic value".
     * @return module The newly created Puffer module
     */
    function createNewRestakingOperator(
        string memory metadataURI,
        address delegationApprover,
        uint32 stakerOptOutWindowBlocks
    ) external returns (IRestakingOperator module);

    /**
     * @notice Create a new Puffer module
     * @dev This function creates a new Puffer module with the given module name
     * @param moduleName The name of the module
     * @return module The newly created Puffer module
     */
    function createNewPufferModule(bytes32 moduleName) external returns (IPufferModule module);

    /**
     * @notice Sets proof Submitter on the Puffer Module
     * @param moduleName The name of the module
     * @param proofSubmitter The address of the proof submitter
     */
    function callSetProofSubmitter(bytes32 moduleName, address proofSubmitter) external;

    /**
     * @notice Starts the checkpointing on puffer modules
     */
    function callStartCheckpoint(address[] calldata moduleAddresses) external;

    /**
     * @notice Calls the modifyOperatorDetails function on the restaking operator
     * @param restakingOperator is the address of the restaking operator
     * @dev See IDelegationManager(EigenLayer) for more details about the other parameters
     * @dev Restricted to the DAO
     */
    function callModifyOperatorDetails(
        IRestakingOperator restakingOperator,
        IDelegationManager.OperatorDetails calldata newOperatorDetails
    ) external;

    /**
     * @notice Calls `queueWithdrawals` from the PufferModule `moduleName`
     * @param moduleName is the name of the module
     * @param sharesAmount is the amount of shares to withdraw
     */
    function callQueueWithdrawals(bytes32 moduleName, uint256 sharesAmount) external;

    /**
     * @notice Calls `completeQueuedWithdrawals` from the PufferModule `moduleName`
     * @dev See IDelegationManager(EigenLayer) for more details about the other parameters
     */
    function callCompleteQueuedWithdrawals(
        bytes32 moduleName,
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) external;

    /**
     * @notice Calls the optIntoSlashing function on the restaking operator
     * @param restakingOperator is the address of the restaking operator
     * @param slasher is the address of the slasher contract to opt into
     * @dev Restricted to the DAO
     */
    function callOptIntoSlashing(IRestakingOperator restakingOperator, address slasher) external;

    /**
     * @notice Calls the updateOperatorMetadataURI function on the restaking operator
     * @param restakingOperator is the address of the restaking operator
     * @param metadataURI is the URI of the operator's metadata
     * @dev Restricted to the DAO
     */
    function callUpdateMetadataURI(IRestakingOperator restakingOperator, string calldata metadataURI) external;

    /**
     * @notice Calls the callDelegateTo function on the target module
     * @param moduleName is the name of the module
     * @param operator is the address of the restaking operator
     * @param approverSignatureAndExpiry the signature of the delegation approver
     * @param approverSalt salt for the signature
     * @dev Restricted to the DAO
     */
    function callDelegateTo(
        bytes32 moduleName,
        address operator,
        ISignatureUtils.SignatureWithExpiry calldata approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external;

    /**
     * @notice Calls the callUndelegate function on the target module
     * @param moduleName is the name of the module
     * @dev Restricted to the DAO
     */
    function callUndelegate(bytes32 moduleName) external returns (bytes32[] memory withdrawalRoot);

    /**
     * @notice Updates AVS registration signature proof
     * @param restakingOperator is the address of the restaking operator
     * @param digestHash is the message hash
     * @param signer is the address of the signature signer
     * @dev Restricted to the DAO
     */
    function updateAVSRegistrationSignatureProof(
        IRestakingOperator restakingOperator,
        bytes32 digestHash,
        address signer
    ) external;

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum exceeds its maximum
     * operator capacity after the operator is registered, this method will fail.
     * @param restakingOperator is the address of the restaking operator
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param socket is the socket of the operator (typically an IP address)
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev Restricted to the DAO
     */
    function callRegisterOperatorToAVS(
        IRestakingOperator restakingOperator,
        address avsRegistryCoordinator,
        bytes calldata quorumNumbers,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata operatorSignature
    ) external;

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum operator
     * capacity, `operatorKickParams` is used to replace an old operator with the new one.
     * @param restakingOperator is the address of the restaking operator
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param socket is the socket of the operator (typically an IP address)
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorKickParams used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums
     * @param churnApproverSignature is the signature of the churnApprover over the `operatorKickParams`
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev Restricted to the DAO
     */
    function callRegisterOperatorToAVSWithChurn(
        IRestakingOperator restakingOperator,
        address avsRegistryCoordinator,
        bytes calldata quorumNumbers,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        IRegistryCoordinator.OperatorKickParam[] calldata operatorKickParams,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata churnApproverSignature,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata operatorSignature
    ) external;

    /**
     * @notice Deregisters the caller from one or more quorums
     * @param restakingOperator is the address of the restaking operator
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being deregistered from
     * @dev Restricted to the DAO
     */
    function callDeregisterOperatorFromAVS(
        IRestakingOperator restakingOperator,
        address avsRegistryCoordinator,
        bytes calldata quorumNumbers
    ) external;

    /**
     * @notice Updates the socket of the msg.sender given they are a registered operator
     * @param restakingOperator is the address of the restaking operator
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param socket is the new socket of the operator
     * @dev Restricted to the DAO
     */
    function callUpdateOperatorAVSSocket(
        IRestakingOperator restakingOperator,
        address avsRegistryCoordinator,
        string memory socket
    ) external;

    /**
     * @notice Calls the `callSetClaimerFor` function on the target module or restaking operator contract
     * @param moduleOrReOp is the address of the target module or restaking operator contract
     * @param claimer is the address of the claimer to be set
     * @dev Restricted to the DAO
     */
    function callSetClaimerFor(address moduleOrReOp, address claimer) external;

    /**
     * @notice Calls the `target` contract with `customCalldata` from the Restaking Operator contract
     * @param restakingOperator is the Restaking Operator contract
     * @param target is the address of the target contract that ReOp will call
     * @param customCalldata is the calldata to be passed to the target contract
     * @dev Restricted to the DAO
     */
    function customExternalCall(IRestakingOperator restakingOperator, address target, bytes calldata customCalldata)
        external;
}
