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
     * @notice Data required for bridging.
     * @param destinationDomainId The destination domain ID.
     */
    struct BridgeData {
        // using struct to allow future addition to this
        uint32 destinationDomainId;
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
     * @notice Parameters for minting and bridging rewards (calldata).
     * @param rewardsAmount The amount of rewards to be bridged.
     * @param ethToPufETHRate The exchange rate from ETH to pufETH.
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param rewardsRoot The merkle root of the rewards.
     * @param rewardsURI The URI for the rewards metadata.
     */
    struct MintAndBridgeData {
        uint256 rewardsAmount;
        uint256 ethToPufETHRate;
        uint256 startEpoch;
        uint256 endEpoch;
        bytes32 rewardsRoot;
        string rewardsURI;
    }

    /**
     * @notice Constructor parameters for bridging.
     * @param xToken The address of the xToken contract.
     * @param lockBox The address of the lockBox contract.
     * @param l2RewardManager The address of the L2 reward manager.
     */
    struct BridgingConstructorParams {
        address xToken;
        address lockBox;
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
    event BridgeDataUpdated(address indexed bridge, BridgeData bridgeData);

    /**
     * @notice Mints and bridges rewards according to the provided parameters.
     * @param params The parameters for bridging rewards.
     */
    function mintAndBridgeRewards(MintAndBridgeParams calldata params) external;

    /**
     * @notice Sets the L2 reward claimer.
     * @param bridge The address of the bridge.
     * @param claimer The address of the new claimer.
     */
    function setL2RewardClaimer(address bridge, address claimer) external;

    /**
     * @notice Updates the bridge data.
     * @param bridge The address of the bridge.
     * @param bridgeData The updated bridge data.
     */
    function updateBridgeData(address bridge, BridgeData memory bridgeData) external;

    /**
     * @notice Returns the bridge data for a given bridge.
     * @param bridge The address of the bridge.
     * @return The bridge data.
     */
    function getBridge(address bridge) external view returns (BridgeData memory);
}
