// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

struct RaveEvidence {
    // Preprocessed remote attestation report
    bytes report;
    // Preprocessed RSA signature over the report
    bytes signature;
    // The hash of a whitelisted Intel-signed leaf x509 certificate
    bytes32 leafX509CertDigest;
}
