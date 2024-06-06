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
