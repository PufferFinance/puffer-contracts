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
    /**
     * @dev Timestamp of the last claim of restaking rewards
     */
    uint256 lastClaimTimestamp;
    /**
     * @dev The last block number for when the rewards root was posted
     */
    uint256 lastProofOfRewardsBlockNumber;
    /**
     * @dev Mapping of a blockNumber and the MerkleRoot for that rewards period
     */
    mapping(uint256 blockNumber => bytes32 root) rewardsRoots;
    /**
     * @dev Mapping that stores which validators have claimed the rewards for a certain blockNumber
     */
    mapping(uint256 blockNumber => mapping(address node => bool claimed)) claimedRewards;
}
