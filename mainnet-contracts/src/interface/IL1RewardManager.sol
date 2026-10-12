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
     * @notice Parameters for minting rewards.
     * @param rewardsAmount The ETH amount of the rewards.
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param rewardsRoot The merkle root of the rewards.
     * @param rewardsURI The URI for the rewards metadata.
     */
    struct MintRewardsParams {
        uint256 rewardsAmount;
        uint256 startEpoch;
        uint256 endEpoch;
        bytes32 rewardsRoot;
        string rewardsURI;
    }

    /**
     * @notice A single claim.
     * @param intervalId The interval ID (see `getIntervalId`).
     * @param amount The ETH amount of the rewards. It is converted to pufETH with the rate of the interval.
     * @param isL1Contract The flag stored in the merkle leaf. It is part of the leaf, but it has no effect on L1.
     * @param account The account that earned the rewards. The pufETH is always sent to this account.
     * @param merkleProof The merkle proof of the leaf.
     */
    struct ClaimOrder {
        bytes32 intervalId;
        uint256 amount;
        bool isL1Contract;
        address account;
        bytes32[] merkleProof;
    }

    /**
     * @notice Mints the pufETH rewards of an interval into this contract and stores the merkle root.
     * The rewards can be claimed after the claiming delay.
     * @dev Restricted to `ROLE_ID_REWARDS_MINTER`
     */
    function mintRewards(MintRewardsParams calldata params) external;

    /**
     * @notice Claims rewards. Anyone can submit the claims, the pufETH is always sent to the `account` of each claim.
     * @dev Restricted in this context is like the `whenNotPaused` modifier from Pausable.sol
     */
    function claimRewards(ClaimOrder[] calldata claimOrders) external;

    /**
     * @notice Freezes the claiming of the newest interval. It is possible only during the claiming delay.
     * A frozen interval can only be reverted.
     * @dev Restricted to `ROLE_ID_REWARD_WATCHER`
     * The DAO can freeze and revert in one call with `freezeAndRevertInterval`
     */
    function freezeInterval(uint256 startEpoch, uint256 endEpoch) external;

    /**
     * @notice Reverts a frozen interval. The minted pufETH is burned.
     * @dev Restricted to `ROLE_ID_DAO`
     */
    function revertInterval(uint256 startEpoch, uint256 endEpoch) external;

    /**
     * @notice Freezes and reverts the newest interval in one call
     * @dev Restricted to `ROLE_ID_DAO`
     */
    function freezeAndRevertInterval(uint256 startEpoch, uint256 endEpoch) external;

    /**
     * @notice Returns the interval ID for a given start and end epoch
     */
    function getIntervalId(uint256 startEpoch, uint256 endEpoch) external pure returns (bytes32);

    /**
     * @notice Returns the record of the interval
     */
    function getInterval(bytes32 intervalId) external view returns (L1RewardManagerStorage.Interval memory);

    /**
     * @notice Returns `true` if the `account` claimed the rewards of the interval
     */
    function isClaimed(bytes32 intervalId, address account) external view returns (bool);

    /**
     * @notice Returns `true` if the rewards of the interval can not be claimed at the moment
     * @dev An interval that does not exist, is frozen, is reverted or is still in its claiming delay is locked
     * `false` does not mean that a claim will succeed. `claimRewards` can still revert, for example when the
     * contract is paused, the account already claimed, or the merkle proof is not valid
     */
    function isClaimingLocked(bytes32 intervalId) external view returns (bool);

    /**
     * @notice Returns the claiming delay that is used for new intervals
     */
    function getClaimingDelay() external view returns (uint256);

    /**
     * @notice Returns the ID of the newest minted interval
     */
    function getNewestIntervalId() external view returns (bytes32);

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
     * @notice Error indicating an invalid address.
     */
    error InvalidAddress();

    /**
     * @notice Error indicating an invalid rewards root.
     */
    error InvalidRewardsRoot();

    /**
     * @notice Error indicating that the start epoch is invalid (not greater than last processed end epoch).
     */
    error InvalidStartEpoch();

    /**
     * @notice Error indicating that the end epoch is lower than the start epoch.
     */
    error InvalidEndEpoch();

    /**
     * @notice Error indicating an invalid claiming delay.
     */
    error InvalidClaimingDelay();

    /**
     * @notice Thrown if a new interval is minted while the newest interval is still in its claiming delay or frozen
     * @dev This makes sure that only the newest interval can ever be frozen and reverted
     */
    error PreviousIntervalLocked(bytes32 intervalId);

    /**
     * @notice Thrown if the interval already exists and is not reverted
     */
    error IntervalAlreadyExists(bytes32 intervalId);

    /**
     * @notice Thrown if the interval does not exist or is reverted
     */
    error InvalidClaimingInterval(bytes32 intervalId);

    /**
     * @notice Thrown if the interval is frozen
     */
    error IntervalIsFrozen(bytes32 intervalId);

    /**
     * @notice Thrown if the `account` tries to claim the rewards before the claiming delay has passed
     */
    error ClaimingLocked(bytes32 intervalId, address account, uint256 lockedUntil);

    /**
     * @notice Thrown if the `account` already claimed the rewards for the interval
     */
    error AlreadyClaimed(bytes32 intervalId, address account);

    /**
     * @notice Thrown if the merkle proof supplied is not valid
     */
    error InvalidProof();

    /**
     * @notice Thrown if a claim would pay out more pufETH than was minted for the interval
     */
    error ClaimExceedsIntervalRewards(bytes32 intervalId);

    /**
     * @notice Thrown if the rewards interval cannot be frozen
     */
    error UnableToFreezeInterval();

    /**
     * @notice Thrown if the rewards interval cannot be reverted
     */
    error UnableToRevertInterval();

    /**
     * @notice Event emitted when the rewards of an interval are minted.
     * @param intervalId The interval ID (see `getIntervalId`).
     * @param rewardsRoot The merkle root of the rewards.
     * @param rewardsAmount The ETH amount of the rewards.
     * @param pufETHAmount The pufETH amount minted for the rewards.
     * @param ethToPufETHRate The exchange rate from ETH to pufETH.
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param claimableAt The timestamp from which the rewards can be claimed.
     * @param rewardsURI The URI for the rewards metadata.
     */
    event RewardsMinted(
        bytes32 indexed intervalId,
        bytes32 indexed rewardsRoot,
        uint256 rewardsAmount,
        uint256 pufETHAmount,
        uint256 ethToPufETHRate,
        uint256 startEpoch,
        uint256 endEpoch,
        uint256 claimableAt,
        string rewardsURI
    );

    /**
     * @notice Event emitted when rewards are claimed
     * @param account The account that earned and received the rewards
     * @param intervalId The interval ID (see `getIntervalId`).
     * @param amount The ETH amount of the rewards
     * @param pufETHAmount The pufETH amount sent to the account
     */
    event RewardsClaimed(address indexed account, bytes32 indexed intervalId, uint256 amount, uint256 pufETHAmount);

    /**
     * @notice Event emitted when an interval is frozen
     * @param intervalId The interval ID (see `getIntervalId`).
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     */
    event IntervalFrozen(bytes32 indexed intervalId, uint256 startEpoch, uint256 endEpoch);

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
     * @notice Event emitted when the claiming delay is updated
     * @param oldDelay The old claiming delay in seconds
     * @param newDelay The new claiming delay in seconds
     */
    event ClaimingDelayUpdated(uint256 oldDelay, uint256 newDelay);
}
