// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { StoppedValidatorInfo } from "./struct/StoppedValidatorInfo.sol";

/* solhint-disable func-named-parameters */

/**
 * @title LibGuardianMessages
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
library LibGuardianMessages {
    using MessageHashUtils for bytes32;

    /**
     * @notice Returns the message that the guardian's enclave needs to sign
     * @param pufferModuleIndex is the validator index in Puffer
     * @param signature is the BLS signature of the deposit data
     * @param withdrawalCredentials are the withdrawal credentials for this validator
     * @param depositDataRoot is the hash of the deposit data
     * @return hash of the data
     */
    function _getBeaconDepositMessageToBeSigned(
        uint256 pufferModuleIndex,
        bytes memory pubKey,
        bytes memory signature,
        bytes memory withdrawalCredentials,
        bytes32 depositDataRoot
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(pufferModuleIndex, pubKey, withdrawalCredentials, signature, depositDataRoot))
            .toEthSignedMessageHash();
    }

    /**
     * @notice Returns the message to be signed for skip provisioning
     * @param moduleName is the name of the module
     * @param index is the index of the skipped validator
     * @return the message to be signed
     */
    function _getSkipProvisioningMessage(bytes32 moduleName, uint256 index) internal pure returns (bytes32) {
        // All guardians use the same nonce
        return keccak256(abi.encode(moduleName, index)).toEthSignedMessageHash();
    }

    /**
     * @notice Returns the message to be signed for handling the batch withdrawal
     * @param validatorInfos is an array of validator information
     * @param deadline is the deadline for the signature
     * @return the message to be signed
     */
    function _getHandleBatchWithdrawalMessage(StoppedValidatorInfo[] memory validatorInfos, uint256 deadline)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(validatorInfos, deadline)).toEthSignedMessageHash();
    }

    /**
     * @notice Returns the message to be signed updating the number of validators
     * @param numberOfValidators is the new number of validators
     * @param epochNumber is the epoch number
     * @return the message to be signed
     */
    function _getSetNumberOfValidatorsMessage(uint256 numberOfValidators, uint256 epochNumber)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(numberOfValidators, epochNumber)).toEthSignedMessageHash();
    }

    /**
     * @notice Returns the message to be signed for the no restaking module rewards root
     * @param moduleName is the name of the module
     * @param root is the root of the no restaking module rewards
     * @param blockNumber is the block number of the no restaking module rewards
     * @return the message to be signed
     */
    function _getModuleRewardsRootMessage(bytes32 moduleName, bytes32 root, uint256 blockNumber)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(moduleName, root, blockNumber)).toEthSignedMessageHash();
    }

    /**
     * @notice Returns the message to be signed for the total epochs validated
     * @param node is the node operator address
     * @param totalEpochsValidated is the total epochs validated
     * @param nonce is the nonce for the node and the function selector
     * @param deadline is the deadline of the signature
     * @return the message to be signed
     */
    function _getTotalEpochsValidatedMessage(
        address node,
        uint256 totalEpochsValidated,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(node, totalEpochsValidated, nonce, deadline)).toEthSignedMessageHash();
    }

    /**
     * @notice Returns the message to be signed for the withdrawal request
     * @param node is the node operator address
     * @param pubKey is the public key
     * @param gweiAmount is the amount in gwei
     * @param nonce is the nonce for the node and the function selector
     * @param deadline is the deadline of the signature
     * @return the message to be signed
     */
    function _getWithdrawalRequestMessage(
        address node,
        bytes memory pubKey,
        uint256 gweiAmount,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(node, pubKey, gweiAmount, nonce, deadline)).toEthSignedMessageHash();
    }
}
/* solhint-disable func-named-parameters */
