// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @custom:storage-location erc7201:L2RewardManager.storage
 * @dev +-----------------------------------------------------------+
 *      |                                                           |
 *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
 *      |                                                           |
 *      +-----------------------------------------------------------+
 */
struct RewardManagerStorage {
    /**
     * @notice Mapping to track reward roots for each unique epoch range
     */
    mapping(uint64 startEpoch => mapping(uint64 endEpoch => bytes32 rewardRoot)) rewardRoots;
    /**
     * @notice Mapping to track claimed tokens for users for each unique epoch range
     */
    mapping(uint64 startEpoch => mapping(uint64 endEpoch => mapping(address account => bool claimed))) claimedRewards;
}
