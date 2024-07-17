// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferVaultV2 } from "./IPufferVaultV2.sol";

/**
 * @title IPufferVaultV3
 * @notice Interface for the PufferVault version 3 contract.
 * @custom:security-contact security@puffer.fi
 */
interface IPufferVaultV3 is IPufferVaultV2 {
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
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param rewardsRoot The merkle root of the rewards.
     * @param rewardsURI The URI for the rewards metadata.
     */
    struct MintAndBridgeParams {
        uint88 rewardsAmount;
        uint64 startEpoch;
        uint64 endEpoch;
        bytes32 rewardsRoot;
        string rewardsURI;
    }

    /**
     * @notice Constructor parameters for bridging.
     * @param connext The address of the Connext contract.
     * @param xToken The address of the xToken contract.
     * @param lockBox The address of the lockBox contract.
     * @param destinationDomain The destination domain ID.
     * @param l2RewardManager The address of the L2 reward manager.
     */
    struct BridgingConstructorParams {
        address connext;
        address xToken;
        address lockBox;
        uint32 destinationDomain;
        address l2RewardManager;
    }

    /**
     * @notice Error indicating an invalid mint amount.
     */
    error InvalidMintAmount();

    /**
     * @notice Error indicating a disallowed mint frequency.
     */
    error NotAllowedMintFrequency();

    /**
     * @notice Event emitted when rewards are minted and bridged.
     * @param rewardsAmount The amount of rewards minted and bridged.
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param rewardsRoot The merkle root of the rewards.
     * @param rewardsURI The URI for the rewards metadata.
     */
    event MintedAndBridgedRewards(
        uint88 rewardsAmount, uint64 startEpoch, uint64 endEpoch, bytes32 indexed rewardsRoot, string rewardsURI
    );

    /**
     * @notice Event emitted when the allowed reward mint amount is updated.
     * @param oldAmount The old allowed reward mint amount.
     * @param newAmount The new allowed reward mint amount.
     */
    event AllowedRewardMintAmountUpdated(uint88 oldAmount, uint88 newAmount);

    /**
     * @notice Event emitted when the allowed reward mint frequency is updated.
     * @param oldFrequency The old allowed reward mint frequency.
     * @param newFrequency The new allowed reward mint frequency.
     */
    event AllowedRewardMintFrequencyUpdated(uint24 oldFrequency, uint24 newFrequency);

    /**
     * @notice Event emitted when the L2 reward claimer is updated.
     * @param account The account setting the claimer.
     * @param claimer The address of the new claimer.
     */
    event L2RewardClaimerUpdated(address account, address claimer);

    /**
     * @notice Mints and bridges rewards according to the provided parameters.
     * @param params The parameters for bridging rewards.
     */
    function mintAndBridgeRewards(MintAndBridgeParams calldata params) external payable;

    /**
     * @notice Sets the L2 reward claimer.
     * @param claimer The address of the new claimer.
     */
    function setL2RewardClaimer(address claimer) external payable;
}
