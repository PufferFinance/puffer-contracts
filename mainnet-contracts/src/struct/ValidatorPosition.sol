// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @dev Struct to indicate the module it belongs to and the index of the validator in the module
 * @dev Packed in 1 storage slot
 */
struct ValidatorPosition {
    address moduleAddress;
    uint96 index;
}