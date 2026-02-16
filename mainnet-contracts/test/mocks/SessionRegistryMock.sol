// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    CVMSession,
    PublicIdentity
} from "@automata-network/automata-tee-workload-measurement/interfaces/registries/ISessionRegistry.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SessionRegistryMock {

    mapping(bytes32 sessionId => bytes32 ownerFingerPrint) private _sessionOwners;
    mapping(bytes32 sessionId => bytes32 workload) private _sessionWorkloads;

    function getSession(bytes32 sessionId) external view returns (CVMSession memory session) {
        return CVMSession({
            akPubKeyFingerprint: _sessionOwners[sessionId], // Attestation Key (root of trust)
            tpmSigningKeyFingerprint: bytes32(0), // TPM Signing Key (extracted from quote)
            sessionKeyFingerprint: bytes32(0), // Session Key (operational key)
            baseImageId: bytes32(0), // Associated platform image
            workloadId: _sessionWorkloads[sessionId], // Associated workload
            platformProfileId: bytes32(0), // Platform profile identifier
            measurementVariantId: bytes32(0), // Measurement variant identifier
            registeredAt: 0, // Registration timestamp
            expiresAt: 0 // Expiration timestamp
        });
    }

    function getSessionOwner(bytes32 sessionId) external view returns (bytes32 ownerFingerprint) {
        return _sessionOwners[sessionId];
     }

    function verifySessionSignature(
        bytes32, // sessionId
        PublicIdentity calldata sessionKey,
        bytes32 message,
        bytes calldata signature
    ) external pure returns (bool valid) {
        return _verifySecp256k1(sessionKey.key, message, signature);
    }

    function _verifySecp256k1(bytes calldata key, bytes32 hash, bytes calldata signature)
        internal
        pure
        returns (bool valid)
    {
        // Validate key format: must be 65 bytes starting with 0x04
        if (key.length != 65 || key[0] != 0x04) {
            return false;
        }

        // Derive expected address from public key
        // Skip first byte (0x04 prefix) and hash the x,y coordinates
        address expectedAddress = address(uint160(uint256(keccak256(key[1:65]))));

        // Recover signer address from signature (using calldata variant to avoid copy)
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);

        // Valid only if recovery succeeded and address matches
        return err == ECDSA.RecoverError.NoError && recovered == expectedAddress;
    }

    function setSessionOwner(bytes32 sessionId, bytes32 ownerFingerprint) external {
        _sessionOwners[sessionId] = ownerFingerprint;
    }

    function setSessionWorkload(bytes32 sessionId, bytes32 workload) external {
        _sessionWorkloads[sessionId] = workload;
    }
}
