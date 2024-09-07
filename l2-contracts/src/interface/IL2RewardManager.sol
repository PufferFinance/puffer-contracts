// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { L2RewardManagerStorage } from "../L2RewardManagerStorage.sol";

/**
 * @title IL2RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IL2RewardManager {
    /**
     * @notice Check if the reward has been claimed for a specific period and an account
     * @param intervalId The claiming internal ID (see `getIntervalId`).
     * @param account The address of the account to check
     * @return bool indicating whether the reward has been claimed
     */
    function isClaimed(bytes32 intervalId, address account) external view returns (bool);

    /**
     * @notice Get the epoch record for a specific period
     * @param intervalId The claiming internal ID (see `getIntervalId`).
     * @return EpochRecord The epoch record of exchange rate and reward root
     */
    function getEpochRecord(bytes32 intervalId) external view returns (L2RewardManagerStorage.EpochRecord memory);

    /**
     * @notice Get the rewards claimer for a specific `account`
     */
    function getRewardsClaimer(address account) external view returns (address);

    /**
     * @notice Get the claiming delay
     */
    function getClaimingDelay() external view returns (uint256);

    /**
     * @notice Returns the interval ID for a given start and end epoch
     */
    function getIntervalId(uint256 startEpoch, uint256 endEpoch) external returns (bytes32);

    /**
     * @notice A record of a single order for claim function call.
     * @param intervalId The claiming internal ID (see `getIntervalId`).
     * @param amount The amount of reward to claim.
     * @param isL1Contract The boolean indicating if the account is a smart contract on L1.
     * @param account The address of the account claiming the reward.
     * @param merkleProof The merkle proof to verify the claim.
     */
    struct ClaimOrder {
        bytes32 intervalId;
        uint256 amount;
        bool isL1Contract;
        address account;
        bytes32[] merkleProof;
    }

    /**
     * @notice Claims the rewards for a specific epoch range
     * @param claimOrders The list of orders for claiming.
     */
    function claimRewards(ClaimOrder[] calldata claimOrders) external;

    /**
     * @notice Returns `true` if the claiming is locked for the `intervalId`
     * There is a delay period before between the bridging of the rewards and the claiming.
     */
    function isClaimingLocked(bytes32 intervalId) external view returns (bool);

    /**
     * @notice Event emitted when rewards root and rate are posted
     * @param rewardsAmount The total rewards amount
     * @param ethToPufETHRate The exchange rate from ETH to pufETH
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param intervalId The claiming internal ID (see `getIntervalId`).
     * @param rewardsRoot The merkle root of the rewards
     */
    event RewardRootAndRatePosted(
        uint256 rewardsAmount,
        uint256 ethToPufETHRate,
        uint256 startEpoch,
        uint256 endEpoch,
        bytes32 indexed intervalId,
        bytes32 rewardsRoot
    );

    /**
     * @notice Event emitted when a claimer is set
     * @param account The account to set the claimer for
     * @param claimer The address of the claimer
     */
    event ClaimerSet(address indexed account, address indexed claimer);

    /**
     * @notice Event emitted when the claiming interval is reverted
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param intervalId The claiming internal ID (see `getIntervalId`).
     * @param pufETHAmount The amount of xPufETH
     * @param rewardsRoot The merkle root of the rewards
     */
    event ClaimingIntervalReverted(
        uint256 startEpoch, uint256 endEpoch, bytes32 indexed intervalId, uint256 pufETHAmount, bytes32 rewardsRoot
    );

    /**
     * @notice Event emitted when rewards are claimed
     * @param account The address of the account claiming the rewards
     * @param recipient The address of the recipient of the rewards
     * @param intervalId The claiming internal ID (see `getIntervalId`).
     * @param amount The amount claimed
     */
    event Claimed(address indexed account, address indexed recipient, bytes32 indexed intervalId, uint256 amount);

    /**
     * @notice Event emitted when the delay period is changed
     * @dev The delay is in seconds
     */
    event ClaimingDelayChanged(uint256 oldDelay, uint256 newDelay);

    /**
     * @notice Event emitted when bridge data is updated.
     * @param bridge The address of the bridge.
     * @param bridgeData The updated bridge data.
     */
    event BridgeDataUpdated(address indexed bridge, L2RewardManagerStorage.BridgeData bridgeData);

    /**
     * @notice Emitted when the claiming interval is frozen
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     */
    event ClaimingIntervalFrozen(uint256 startEpoch, uint256 endEpoch);

    /**
     * @notice Thrown if the `account` already claimed the rewards for the interval
     */
    error AlreadyClaimed(bytes32 intervalId, address account);

    /**
     * @notice Thrown if the `account` tries to claim the rewards before the claiming delay has passed
     */
    error ClaimingLocked(bytes32 intervalId, address account, uint256 lockedUntil);

    /**
     * @notice Thrown if the merkle proof supplied is not valid
     */
    error InvalidProof();

    /**
     * @notice Thrown if if the delay period is invalid
     */
    error InvalidDelayPeriod();

    /**
     * @notice Thrown if the new interval would relock the claiming
     */
    error RelockingIntervalIsNotAllowed();

    /**
     * @notice Thrown if the rewards interval cannot be frozen
     */
    error UnableToFreezeInterval();

    /**
     * @notice Thrown if the rewards interval cannot be reverted
     */
    error UnableToRevertInterval();

    /**
     * @notice Error indicating the bridge is not allowlisted.
     */
    error BridgeNotAllowlisted();

    /**
     * @notice Thrown if the L1 address is a smart contract, but the rewards recipient on L2 is not set
     * @dev Smart contrats might have a hard time owning the same address on L2, because of that, they need to set the rewards recipient.
     */
    error ClaimerNotSet(address node);

    /**
     * @notice Thrown if the claiming interval is not valid
     */
    error InvalidClaimingInterval(bytes32 claimingInterval);
}
