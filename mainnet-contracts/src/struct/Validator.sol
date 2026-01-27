// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Status } from "../struct/Status.sol";

/**
 * @dev Validator struct
 */
struct Validator {
    address node; // Address of the Node operator
    uint96 bond; // Validator bond (pufETH amount)
    address module; // In which module is the Validator participating
    Status status; // Validator status
    bytes pubKey; // Validator public key
}

struct PermissionedValidator {
    // Slot 1: node (20) + status (1) + isNonRestaked (1) + stakeAmountGwei (8) = 30 bytes
    address node; // Address of the Node operator
    Status status; // Validator status
    bool isNonRestaked; // true = non-restaked (Beacon Chain), false = restaked (EigenLayer)
    uint64 stakeAmountGwei; // Stake amount in Gwei (32-2048 ETH for non-restaked, always 32 ETH for restaked)
    // Slot 2: module (20 bytes)
    address module; // In which module is the Validator participating
    // Slot 3: pubKey reference (dynamic bytes)
    bytes pubKey; // Validator public key
}
