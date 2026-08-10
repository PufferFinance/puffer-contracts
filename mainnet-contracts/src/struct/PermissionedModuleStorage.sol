// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IEigenPod } from "../interface/Eigenlayer-Slashing/IEigenPod.sol";
import { NonRestakingWithdrawalCredentials } from "../NonRestakingWithdrawalCredentials.sol";

/**
 * @custom:storage-location erc7201:PermissionedModule.storage
 * @dev +-----------------------------------------------------------+
 *      |                                                           |
 *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
 *      |                                                           |
 *      +-----------------------------------------------------------+
 */
struct PermissionedModuleStorage {
    /**
     * @dev Module Name
     */
    bytes32 moduleName;
    /**
     * @dev Owned EigenPod (for restaked validators with 0x01 withdrawal credentials)
     */
    IEigenPod eigenPod;
    /**
     * @dev NonRestakingWithdrawalCredentials contract (for non-restaked validators with 0x02 withdrawal credentials)
     */
    NonRestakingWithdrawalCredentials nonRestakingWithdrawalCredentials;
}
