// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { RestakingOperator } from "src/RestakingOperator.sol";
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
     * @param delegationApprover is the address of the delegation approver
     * @dev Signature "0x28682dddd8aa82d42ec7143a18beba2d09b27d4581f2f26a6afcd0da4576ae71"
     */
    event RestakingOperatorCreated(address indexed restakingOperator, address indexed delegationApprover);

    /**
     * @notice Emitted when the Restaking Operator is modified
     * @param restakingOperator is the address of the restaking operator
     * @param newOperatorDetails is the struct with new operator details
     * @dev Signature "0xee78237d6444cc6c9083c1ef31a82b0feac23fbdf0cf52d7b0ed66dfa5f7f9f2"
     */
    event RestakingOperatorModified(address indexed restakingOperator, address indexed newOperatorDetails);

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
     * @notice Emitted when the Restaking Operator or PufferModule sets the calimer to `claimer`
     * @dev Signature "0x4925eafc82d0c4d67889898eeed64b18488ab19811e61620f387026dec126a28"
     */
    event ClaimerSet(address indexed rewardsReceiver, address indexed claimer);
}
