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
    address node; // Address of the Node operator
    address module; // In which module is the Validator participating
    Status status; // Validator status
    bytes pubKey; // Validator public key
    bool isNonRestaked; // true = non-restaked (Beacon Chain), false = restaked (EigenLayer)
    uint64 stakeAmountGwei; // Stake amount in Gwei (32-2048 ETH for non-restaked, always 32 ETH for restaked)
}
