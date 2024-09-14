// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IEigenPod } from "eigenlayer/interfaces/IEigenPod.sol";

/**
 * @custom:storage-location erc7201:PufferModule.storage
 * @dev +-----------------------------------------------------------+
 *      |                                                           |
 *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
 *      |                                                           |
 *      +-----------------------------------------------------------+
 */
struct ModuleStorage {
    /**
     * @dev Module Name
     */
    bytes32 moduleName;
    /**
     * @dev Owned EigenPod
     */
    IEigenPod eigenPod;
    uint256 _deprecated_lastClaimTimestamp;
    uint256 _deprecated_lastProofOfRewardsBlockNumber;
    mapping(uint256 blockNumber => bytes32 root) _deprecated_rewardsRoots;
    mapping(uint256 blockNumber => mapping(address node => bool claimed)) _deprecated_claimedRewards;
}
