// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @notice Thrown when the operation is not authorized
 * @dev Signature "0x82b42900"
 */
error Unauthorized();

/**
 * @notice Thrown if the address supplied is not valid
 * @dev Signature "0xe6c4247b"
 */
error InvalidAddress();

/**
 * @notice Thrown when amount is not valid
 * @dev Signature "0x2c5211c6"
 */
error InvalidAmount();

/**
 * @notice Thrown when transfer fails
 * @dev Signature "0x90b8ec18"
 */
error TransferFailed();
