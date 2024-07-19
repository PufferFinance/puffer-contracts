// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

    enum BridgingType {
        MintAndBridge,
        SetClaimer
    }

        /**
     * @notice Parameters for bridging actions.
     * @param bridgingType The type of bridging action.
     * @param data The data associated with the bridging action.
     */
    struct BridgingParams {
        BridgingType bridgingType;
        bytes data;
    }

    /**
     * @notice Parameters for setting a claimer.
     * @param account The account setting the claimer.
     * @param claimer The address of the new claimer.
     */
    struct SetClaimerParams {
        address account;
        address claimer;
    }

   /**
     * @notice Parameters for minting and bridging rewards.
     * @param rewardsAmount The amount of rewards to be bridged.
     * @param ethToPufETHRate The exchange rate from ETH to pufETH.
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param rewardsRoot The merkle root of the rewards.
     * @param rewardsURI The URI for the rewards metadata.
     */
    struct MintAndBridgeParams {
        uint128 rewardsAmount;
        uint128 ethToPufETHRate;
        uint64 startEpoch;
        uint64 endEpoch;
        bytes32 rewardsRoot;
        string rewardsURI;
    }

/// @dev A record of a single order for claim function call.
/// @param startEpoch The start epoch of the interval where the merkle root is generated from.
/// @param endEpoch The end epoch of the interval where the merkle root is generated from.
/// @param account The address of the account claiming the reward.
/// @param amount The amount of reward to claim.
/// @param merkleProof The merkle proof to verify the claim.
struct ClaimOrder {
    uint64 startEpoch;
    uint64 endEpoch;
    address account;
    uint256 amount;
    bytes32[] merkleProof;
}
