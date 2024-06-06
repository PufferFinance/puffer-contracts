// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IRegistryCoordinator, IBLSApkRegistry } from "eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";

interface IRegistryCoordinatorExtended is IRegistryCoordinator {
    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum exceeds its maximum
     * operator capacity after the operator is registered, this method will fail.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param socket is the socket of the operator (typically an IP address)
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperator(
        bytes calldata quorumNumbers,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum operator
     * capacity, `operatorKickParams` is used to replace an old operator with the new one.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorKickParams used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums
     * @param churnApproverSignature is the signature of the churnApprover over the `operatorKickParams`
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperatorWithChurn(
        bytes calldata quorumNumbers,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        IRegistryCoordinator.OperatorKickParam[] calldata operatorKickParams,
        ISignatureUtils.SignatureWithSaltAndExpiry memory churnApproverSignature,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    /**
     * @notice Deregisters the caller from one or more quorums
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being deregistered from
     */
    function deregisterOperator(bytes calldata quorumNumbers) external;

    /**
     * @notice Updates the socket of the msg.sender given they are a registered operator
     * @param socket is the new socket of the operator
     */
    function updateSocket(string memory socket) external;
}
