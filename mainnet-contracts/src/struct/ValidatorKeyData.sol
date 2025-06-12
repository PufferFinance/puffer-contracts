// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @dev Validator Key data struct
 */
struct ValidatorKeyData {
    bytes blsPubKey;
    bytes signature;
    bytes32 depositDataRoot;
    uint8 numBatches;
}
