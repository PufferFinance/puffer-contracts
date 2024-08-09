// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISlasher } from "eigenlayer/interfaces/ISlasher.sol";
import { IRegistryCoordinator, IBLSApkRegistry } from "eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";

/**
 * @title IRestakingOperator
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IRestakingOperator {
    /**
     * @notice Returns the EigenLayer's DelegationManager
     */
    function EIGEN_DELEGATION_MANAGER() external view returns (IDelegationManager);

    /**
     * @notice Returns the EigenLayer's Slasher
     */
    function EIGEN_SLASHER() external view returns (ISlasher);

    /**
     * @notice Modify the operator details
     * @param newOperatorDetails is the struct with new operator details
     * @dev Restricted to the PufferModuleManager
     */
    function modifyOperatorDetails(IDelegationManager.OperatorDetails calldata newOperatorDetails) external;

    /**
     * @notice Opts the restaking operator into slashing by the slasher
     * @param slasher is the address of the slasher contract to opt into
     * @dev Restricted to the PufferModuleManager
     */
    function optIntoSlashing(address slasher) external;

    /**
     * @notice Updates the operator's metadata URI
     * @param metadataURI is the URI of the operator's metadata
     * @dev Restricted to the PufferModuleManager
     */
    function updateOperatorMetadataURI(string calldata metadataURI) external;

    /**
     * @notice Updates a signature proof by setting the signer address of the message hash
     * @param digestHash is message hash
     * @param signer is the signer address
     * @dev Restricted to the PufferModuleManager
     */
    function updateSignatureProof(bytes32 digestHash, address signer) external;

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum exceeds its maximum
     * operator capacity after the operator is registered, this method will fail.
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param socket is the socket of the operator (typically an IP address)
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperatorToAVS(
        address avsRegistryCoordinator,
        bytes calldata quorumNumbers,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata operatorSignature
    ) external;

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum operator
     * capacity, `operatorKickParams` is used to replace an old operator with the new one.
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorKickParams used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums
     * @param churnApproverSignature is the signature of the churnApprover over the `operatorKickParams`
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperatorToAVSWithChurn(
        address avsRegistryCoordinator,
        bytes calldata quorumNumbers,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        IRegistryCoordinator.OperatorKickParam[] calldata operatorKickParams,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata churnApproverSignature,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata operatorSignature
    ) external;

    /**
     * @notice Does a custom call to `target` with `customCalldata`
     * @return response
     */
    function customCalldataCall(address target, bytes calldata customCalldata)
        external
        returns (bytes memory response);

    /**
     * @notice Deregisters the caller from one or more quorums
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being deregistered from
     */
    function deregisterOperatorFromAVS(address avsRegistryCoordinator, bytes calldata quorumNumbers) external;

    /**
     * @notice Updates the socket of the msg.sender given they are a registered operator
     * @param avsRegistryCoordinator the avs registry coordinator address
     * @param socket is the new socket of the operator
     */
    function updateOperatorAVSSocket(address avsRegistryCoordinator, string memory socket) external;

    /**
     * @notice Sets the rewards claimer to `claimer` for the RestakingOperator
     */
    function callSetClaimerFor(address claimer) external;
}
