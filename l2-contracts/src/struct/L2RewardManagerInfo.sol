// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @notice A record of a single order for claim function call.
 * @param startEpoch The start epoch of the interval where the merkle root is generated from.
 * @param endEpoch The end epoch of the interval where the merkle root is generated from.
 * @param amount The amount of reward to claim.
 * @param account The address of the account claiming the reward.
 * @param merkleProof The merkle proof to verify the claim.
 */
struct ClaimOrder {
    uint256 startEpoch;
    uint256 endEpoch;
    uint256 amount;
    address account;
    bytes32[] merkleProof;
}

/**
 * @notice A record of a single epoch for storing the rate and root.
 * @param ethToPufETHRate The exchange rate from ETH to pufETH.
 * @param rewardRoot The merkle root of the rewards.
 */
struct EpochRecord {
    uint256 ethToPufETHRate;
    bytes32 rewardRoot;
}
