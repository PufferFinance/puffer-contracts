// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { RaveEvidence } from "../struct/RaveEvidence.sol";

/**
 * @title IEnclaveVerifier interface
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IEnclaveVerifier {
    struct RSAPubKey {
        bytes modulus;
        bytes exponent;
    }

    /**
     * @notice Thrown if the Evidence that we're trying to verify is stale
     * Evidence should be submitted for the recent block < `FRESHNESS_BLOCKS`
     * @dev Signature "0x5d4ad9a9"
     */
    error StaleEvidence();

    /**
     * @notice Emitted when the `pubKeyHash` is added to valid pubKeys
     * @dev Signature "0x13b85b042d2bb270091da7111e3b3cc407f6b86c85882cf48ae94123cae22b17"
     */
    event AddedPubKey(bytes32 indexed pubKeyHash);

    /**
     * @notice Emitted when the `pubKeyHash` is removed from valid pubKeys
     * @dev Signature "0x0ebd07953ae533bded7d9b0715fa49e0a0ed0a6cef4638a685737ffef8b86254"
     */
    event RemovedPubKey(bytes32 indexed pubKeyHash);

    /**
     * @notice Getter for intelRootCAPubKey
     */
    function getIntelRootCAPubKey() external pure returns (RSAPubKey memory);

    /**
     * @notice Adds a leaf x509 RSA public key if the x509 was signed by Intel's root CA
     * @param leafX509Cert certificate
     */
    function addLeafX509(bytes calldata leafX509Cert) external;

    /**
     * @notice Verifies remote attestation evidence: the report contains the expected MRENCLAVE/MRSIGNER values, a valid TCB status, and was signed by an Intel-issued x509 certificate. The report will contain a 64B payload in the form (32B_Commitment || 32B_BlockHash), where 32B_Blockhash is a recent L1 blockhash and 32B_Commitment is a keccak256 hash that the enclave is committing to. The calling contract is expected to precompute raveCommitment from public inputs. The function returns true if the report is valid and the extracted payload matches the expected.
     * @param blockNumber is the block number to fetch 32B_Blockhash
     * @param raveCommitment is the keccak256 hash commitment 32B_Commitment
     * @param evidence is the remote attestation evidence
     * @param mrenclave is the MRENCLAVE value expected by the calling contract
     * @param mrsigner is the MRSIGNER value expected by the calling contract
     * @return true if evidence verification is a success
     */
    function verifyEvidence(
        uint256 blockNumber,
        bytes32 raveCommitment,
        RaveEvidence calldata evidence,
        bytes32 mrenclave,
        bytes32 mrsigner
    ) external view returns (bool);
}
