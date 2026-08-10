// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @custom:storage-location erc7201:NonRestakingWithdrawalCredentials.storage
 * @dev +-----------------------------------------------------------+
 *      |                                                           |
 *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
 *      |                                                           |
 *      +-----------------------------------------------------------+
 */
struct NRWCStorage {
    /**
     * @dev The PermissionedModule that owns this NRWC contract
     */
    address permissionedModule;
}
