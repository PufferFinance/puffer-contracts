// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;


/**
 * @dev Parameters for bridging from PufferVaultV3 to L2RewardManager
 */
struct BridgingParams {
    uint128 rewardsAmount; 
    uint64 startEpoch;
    uint64 endEpoch;
    bytes32 rewardsRoot;
    string rewardsURI;
}