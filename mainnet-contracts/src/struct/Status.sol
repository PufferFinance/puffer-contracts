// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @dev Validator Status
 */
enum Status {
    UNINITIALIZED,
    PENDING,
    SKIPPED,
    ACTIVE,
    FROZEN
}
