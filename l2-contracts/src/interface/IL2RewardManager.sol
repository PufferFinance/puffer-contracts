// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IL2RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IL2RewardManager {
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
     * @param timeBridged The timestamp of then the rewars were bridged to L2.
     */
    struct EpochRecord {
        uint256 ethToPufETHRate;
        bytes32 rewardRoot;
        uint256 timeBridged;
    }

    /**
     * @notice Check if the reward has been claimed for a specific period and an account
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param account The address of the account to check
     * @return bool indicating whether the reward has been claimed
     */
    function isClaimed(uint256 startEpoch, uint256 endEpoch, address account) external view returns (bool);

    /**
     * @notice Get the epoch record for a specific period
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @return EpochRecord The epoch record of exchange rate and reward root
     */
    function getEpochRecord(uint256 startEpoch, uint256 endEpoch) external view returns (EpochRecord memory);

    /**
     * @notice Get the rewards claimer for a specific `account`
     */
    function getRewardsClaimer(address account) external view returns (address);

    /**
     * @notice The receiver function as required by the IXReceiver interface.
     * @dev The Connext bridge contract will call this function.
     * @dev Restricted to the whitelisted Bridge contract only
     * @dev The origin sender must be the L1 PufferVaultV3 contract
     * @param transferId The transfer ID
     * @param amount The amount transferred
     * @param asset The asset transferred
     * @param originSender The address of the origin sender
     * @param origin The origin chain ID
     * @param callData The call data
     * @return bytes The result of the call
     */
    function xReceive(
        bytes32 transferId,
        uint256 amount,
        address asset,
        address originSender,
        uint32 origin,
        bytes memory callData
    ) external returns (bytes memory);

    /**
     * @notice Claims the rewards for a specific epoch range
     * @param claimOrders The list of orders for claiming.
     */
    function claimRewards(ClaimOrder[] calldata claimOrders) external;

    /**
     * @notice Event emitted when rewards root and rate are posted
     * @param rewardsAmount The total rewards amount
     * @param ethToPufETHRate The exchange rate from ETH to pufETH
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param root The merkle root of the rewards
     */
    event RewardRootAndRatePosted(
        uint256 rewardsAmount, uint256 ethToPufETHRate, uint256 startEpoch, uint256 endEpoch, bytes32 root
    );

    /**
     * @notice Event emitted when a claimer is set
     * @param account The account to set the claimer for
     * @param claimer The address of the claimer
     */
    event ClaimerSet(address indexed account, address indexed claimer);

    /**
     * @notice Event emitted when rewards are claimed
     * @param account The address of the account claiming the rewards
     * @param recipient The address of the recipient of the rewards
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param amount The amount claimed
     */
    event Claimed(
        address indexed account, address indexed recipient, uint256 startEpoch, uint256 endEpoch, uint256 amount
    );

    /**
     * @notice Event emitted when the delay period is changed
     * @dev The delay is in seconds
     */
    event ClaimingDelayChanged(uint256 oldDelay, uint256 newDelay);

    /**
     * @notice Thrown if the `account` already claimed the the rewards for the interval
     */
    error AlreadyClaimed(uint256 startEpoch, uint256 endEpoch, address account);

    /**
     * @notice Thrown if the `account` tries to claim the rewards before the claiming delay has passed
     */
    error ClaimingDelayNotPassed(uint256 startEpoch, uint256 endEpoch, address account);

    /**
     * @notice Thrown if the merkle proof supplied is not valid
     */
    error InvalidProof();

    /**
     * @notice Thrown if the tx uses invalid bridge type
     */
    error InvalidBridgingType();

    /**
     * @notice Thrown if if the delay period is invalid
     */
    error InvalidDelayPeriod();
}
