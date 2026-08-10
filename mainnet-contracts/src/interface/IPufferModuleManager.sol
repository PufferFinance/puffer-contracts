// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { RestakingOperator } from "../RestakingOperator.sol";
import { IEigenPodTypes } from "./Eigenlayer-Slashing/IEigenPod.sol";

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
     * @notice Thrown if the input array length is zero
     */
    error InputArrayLengthZero();

    /**
     * @notice Emitted when the Custom Call from the restakingOperator is successful
     * @dev Signature "0x80b240e4b7a31d61bdee28b97592a7c0ad486cb27d11ee5c6b90530db4e949ff"
     */
    event CustomCallSucceeded(address indexed restakingOperator, address target, bytes customCalldata, bytes response);

    /**
     * @notice Emitted when the Restaking Operator is registered to an AVS
     * @param restakingOperator is the address of the restaking operator
     * @param avs is the address of the AVS
     * @param operatorSetId is the id of the operator set
     * @param data is the data passed to the AVS
     * @dev Signature "0xe47a1be2e87cd0d8e7deac93187c98c837de2096e1f048141ab6e377d30d648a"
     */
    event RestakingOperatorRegisteredToAVS(
        address indexed restakingOperator, address indexed avs, uint32[] operatorSetId, bytes data
    );

    /**
     * @notice Emitted when the Restaking Operator is deregistered from an AVS
     * @param restakingOperator is the address of the restaking operator
     * @param avs is the address of the AVS
     * @param operatorSetId is the id of the operator set
     * @dev Signature "0xd3a1da1a6a02235e5cee67b27f99931e657829be79f720ae8bfe10bd80bcd5ae"
     */
    event RestakingOperatorDeregisteredFromAVS(
        address indexed restakingOperator, address indexed avs, uint32[] operatorSetId
    );

    /**
     * @notice Emitted when the Restaking Operator is created
     * @param restakingOperator is the address of the restaking operator
     * @dev Signature "0xc7178e96e72aa500a37cafe2999b91040f28d3d3a83e64eb3b6166345e804291"
     */
    event RestakingOperatorCreated(address indexed restakingOperator);

    /**
     * @notice Emitted when the Withdrawals are queued
     * @param moduleName is the name of the module
     * @param shareAmount is the amount of shares
     * @dev Signature "0xfa1bd67700189b28b5a9085170838266813878ca3237b31a33358644a22a2f0e"
     */
    event WithdrawalsQueued(bytes32 indexed moduleName, uint256 shareAmount, bytes32 withdrawalRoot);

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
     * @notice Emitted when the validators exit is triggered
     * @param moduleName the module name to be exited
     * @param pubkeys the pubkeys of the validators to exit
     * @dev Signature "0x456e0aba5f7f36ec541f2f550d3f5895eb7d1ae057f45e8683952ac182254e5d"
     */
    event ValidatorsExitTriggered(bytes32 indexed moduleName, bytes[] pubkeys);

    /**
     * @notice Emitted when the restaking operator avs signature proof is updated
     * @param restakingOperator is the address of the restaking operator
     * @param digestHash is the message hash
     * @param signer is the address of the signature signer
     * @dev Signature "0x3a6a179c72e503b78f992c3aa1a8d451c366c446c086cee5a811a3d03445a62f"
     */
    event AVSRegistrationSignatureProofUpdated(address indexed restakingOperator, bytes32 digestHash, address signer);

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
     * @notice Emitted when the Restaking Operator or PufferModule sets the claimer to `claimer`
     * @dev Signature "0x4925eafc82d0c4d67889898eeed64b18488ab19811e61620f387026dec126a28"
     */
    event ClaimerSet(address indexed rewardsReceiver, address indexed claimer);

    /**
     * @notice Emitted when queued withdrawals are completed for a permissioned module
     * @param permissionedModule The address of the permissioned module
     * @param sharesWithdrawn The amount of shares withdrawn
     */
    event PermissionedModuleCompletedQueuedWithdrawals(address indexed permissionedModule, uint256 sharesWithdrawn);

    /**
     * @notice Emitted when withdrawals are queued for a permissioned module
     * @param permissionedModule The address of the permissioned module
     * @param shareAmount The amount of shares queued
     * @param withdrawalRoot The withdrawal root
     */
    event PermissionedModuleWithdrawalsQueued(
        address indexed permissionedModule, uint256 shareAmount, bytes32 withdrawalRoot
    );

    /**
     * @notice Emitted when a permissioned module is delegated
     * @param permissionedModule The address of the permissioned module
     * @param operator The operator address
     */
    event PermissionedModuleDelegated(address indexed permissionedModule, address indexed operator);

    /**
     * @notice Emitted when a permissioned module is undelegated
     * @param permissionedModule The address of the permissioned module
     */
    event PermissionedModuleUndelegated(address indexed permissionedModule);

    /**
     * @notice Emitted when restaked validators exit is triggered for a permissioned module
     * @param permissionedModule The address of the permissioned module
     * @param pubkeys The pubkeys of the validators
     */
    event PermissionedRestakedValidatorsExitTriggered(address indexed permissionedModule, bytes[] pubkeys);

    /**
     * @notice Emitted when non-restaked ETH is withdrawn from a permissioned module
     * @param permissionedModule The address of the permissioned module
     */
    event PermissionedNonRestakedETHWithdrawn(address indexed permissionedModule);

    /**
     * @notice Emitted when proof submitter is set for a permissioned module
     * @param permissionedModule The address of the permissioned module
     * @param proofSubmitter The proof submitter address
     */
    event PermissionedProofSubmitterSet(address indexed permissionedModule, address indexed proofSubmitter);

    /**
     * @notice Emitted when claimer is set for a permissioned module
     * @param permissionedModule The address of the permissioned module
     * @param claimer The claimer address
     */
    event PermissionedClaimerSet(address indexed permissionedModule, address indexed claimer);

    /**
     * @notice Emitted when withdrawal requests are triggered for non-restaked validators
     * @param permissionedModule The address of the permissioned module
     * @param requests The withdrawal requests (amountGwei == 0 for full exit, > 0 for partial)
     */
    event PermissionedNonRestakedValidatorWithdrawalsTriggered(
        address indexed permissionedModule, IEigenPodTypes.WithdrawalRequest[] requests
    );

    /**
     * @notice Emitted when ETH is transferred from permissioned modules
     * @param permissionedModules The addresses of the permissioned modules
     * @param amounts The amounts transferred from each module
     * @param recipient The recipient address (vault or external)
     * @param totalAmount The total amount transferred
     */
    event PermissionedModuleETHTransferred(
        address[] permissionedModules, uint256[] amounts, address indexed recipient, uint256 totalAmount
    );
}
