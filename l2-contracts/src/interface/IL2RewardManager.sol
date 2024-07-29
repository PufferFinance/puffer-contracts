// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ClaimOrder, EpochRecord } from "../struct/L2RewardManagerInfo.sol";

/**
 * @title IL2RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IL2RewardManager {
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
     * @notice Custom error for already claimed rewards
     */
    error AlreadyClaimed(uint256 startEpoch, uint256 endEpoch, address account);

    /**
     * @notice Custom error for invalid proof
     */
    error InvalidProof();

    /**
     * @notice Custom error for invalid bridging type
     */
    error InvalidBridgingType();
}
