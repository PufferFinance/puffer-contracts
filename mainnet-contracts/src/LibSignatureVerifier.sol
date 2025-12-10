// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { StoppedValidatorInfo } from "./struct/StoppedValidatorInfo.sol";
import { Unauthorized } from "./Errors.sol";

/* solhint-disable func-named-parameters */

/**
 * @title LibSignatureVerifier
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
library LibSignatureVerifier {
    using MessageHashUtils for bytes32;

    /**
     * @notice Thrown when the BLS public key is not valid
     * @dev Signature "0x7eef7967"
     */
    error InvalidBLSPubKey();

    /**
     * @dev BLS public keys are 48 bytes long
     */
    uint256 internal constant _BLS_PUB_KEY_LENGTH = 48;

    function _validateBatchWithdrawals(
        StoppedValidatorInfo[] calldata validatorInfos,
        bytes calldata paymasterSignature,
        address paymasterAddress
    ) internal pure {
        bytes32 signedMessageHash = keccak256(abi.encode(validatorInfos)).toEthSignedMessageHash();

        (address currentSigner, ECDSA.RecoverError recoverError,) =
            ECDSA.tryRecover(signedMessageHash, paymasterSignature);
        require(recoverError == ECDSA.RecoverError.NoError && currentSigner == paymasterAddress, Unauthorized());
    }

    function _checkBLSPubKey(bytes calldata pubKey) internal pure {
        require(pubKey.length != _BLS_PUB_KEY_LENGTH, InvalidBLSPubKey());
    }
}
