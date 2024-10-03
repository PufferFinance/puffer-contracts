// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { L1RewardManagerStorage } from "../L1RewardManagerStorage.sol";

/**
 * @title IL1RewardManager interface
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IL1RewardManager {
    /**
     * @notice Sets the rewards claimer on L2.
     * Smart contracts might not be able to to own the same address on L2. This function allows to set a different address as the claimer.
     * msg.value is used to pay for the relayer fee on the destination chain.
     *
     * @param bridge The address of the bridge.
     * @param claimer The address of the new claimer.
     */
    function setL2RewardClaimer(address bridge, address claimer) external payable;

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
        IL1RewardManager.BridgingType bridgingType;
        bytes data;
    }

    /**
     * @notice Parameters for minting and bridging rewards.
     * @param bridge The address of the bridge.
     * @param rewardsAmount The amount of rewards to be bridged.
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param rewardsRoot The merkle root of the rewards.
     * @param rewardsURI The URI for the rewards metadata.
     */
    struct MintAndBridgeParams {
        address bridge;
        uint256 rewardsAmount;
        uint256 startEpoch;
        uint256 endEpoch;
        bytes32 rewardsRoot;
        string rewardsURI;
    }

    /**
     * @notice Error indicating an invalid mint amount.
     */
    error InvalidMintAmount();

    /**
     * @notice Error indicating a disallowed mint frequency.
     */
    error InvalidMintFrequency();

    /**
     * @notice Error indicating a disallowed mint frequency.
     */
    error NotAllowedMintFrequency();

    /**
     * @notice Error indicating the bridge is not allowlisted.
     */
    error BridgeNotAllowlisted();

    /**
     * @notice Error indicating an invalid address.
     */
    error InvalidAddress();

    /**
     * @notice Event emitted when rewards are minted and bridged.
     * @param rewardsAmount The amount of rewards minted and bridged.
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param rewardsRoot The merkle root of the rewards.
     * @param ethToPufETHRate The exchange rate from ETH to pufETH.
     * @param rewardsURI The URI for the rewards metadata.
     */
    event MintedAndBridgedRewards(
        uint256 rewardsAmount,
        uint256 startEpoch,
        uint256 endEpoch,
        bytes32 indexed rewardsRoot,
        uint256 ethToPufETHRate,
        string rewardsURI
    );

    /**
     * @param rewardsAmount The amount of rewards reverted.
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param rewardsRoot The merkle root of the rewards.
     */
    event RevertedRewards(uint256 rewardsAmount, uint256 startEpoch, uint256 endEpoch, bytes32 indexed rewardsRoot);

    /**
     * @notice Event emitted when the allowed reward mint amount is updated.
     * @param oldAmount The old allowed reward mint amount.
     * @param newAmount The new allowed reward mint amount.
     */
    event AllowedRewardMintAmountUpdated(uint256 oldAmount, uint256 newAmount);

    /**
     * @notice Event emitted when the allowed reward mint frequency is updated.
     * @param oldFrequency The old allowed reward mint frequency.
     * @param newFrequency The new allowed reward mint frequency.
     */
    event AllowedRewardMintFrequencyUpdated(uint256 oldFrequency, uint256 newFrequency);

    /**
     * @notice Event emitted when the L2 reward claimer is updated.
     * @param account The account setting the claimer.
     * @param claimer The address of the new claimer.
     */
    event L2RewardClaimerUpdated(address indexed account, address indexed claimer);

    /**
     * @notice Event emitted when bridge data is updated.
     * @param bridge The address of the bridge.
     * @param bridgeData The updated bridge data.
     */
    event BridgeDataUpdated(address indexed bridge, L1RewardManagerStorage.BridgeData bridgeData);
}
