// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ClaimOrder} from "../struct/RewardManagerInfo.sol";

interface IL2RewardManager {
    /**
     * @notice Check if a token has been claimed for a specific epoch range and account
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param account The address of the account to check
     * @return bool indicating whether the reward has been claimed
     */
    function isClaimed(
        uint64 startEpoch,
        uint64 endEpoch,
        address account
    ) external view returns (bool);

    /**
     * @notice The receiver function as required by the IXReceiver interface.
     * @dev The Connext bridge contract will call this function.
     * @param _transferId The transfer ID
     * @param _amount The amount transferred
     * @param _asset The asset transferred
     * @param _originSender The address of the origin sender
     * @param _origin The origin chain ID
     * @param _callData The call data
     * @return bytes The result of the call
     */
    function xReceive(
        bytes32 _transferId,
        uint256 _amount,
        address _asset,
        address _originSender,
        uint32 _origin,
        bytes memory _callData
    ) external returns (bytes memory);

    /**
     * @notice Posts the updated rewards root for a specific epoch range
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param root The merkle root of the rewards
     */
    function postRewardsRoot(
        uint64 startEpoch,
        uint64 endEpoch,
        bytes32 root
    ) external;

    /**
     * @notice Claims the rewards for a specific epoch range
     * @param claimOrders The list of orders for claiming.
     */
    function claimRewards(ClaimOrder[] calldata claimOrders) external;

    /**
     * @notice Event emitted when reward amount is received
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param rewardsRoot The merkle root of the rewards
     * @param rewardsAmount The total rewards amount
     */
    event RewardAmountReceived(
        uint64 startEpoch,
        uint64 endEpoch,
        bytes32 rewardsRoot,
        uint128 rewardsAmount
    );

    /**
     * @notice Event emitted when rewards root is posted
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param root The merkle root of the rewards
     */
    event RewardsRootPosted(uint64 startEpoch, uint64 endEpoch, bytes32 root);

    /**
     * @notice Event emitted when rewards are claimed
     * @param account The address of the account claiming the rewards
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param amount The amount claimed
     */
    event Claimed(
        address indexed account,
        uint64 startEpoch,
        uint64 endEpoch,
        uint256 amount
    );

    /**
     * @notice Custom error for invalid asset
     */
    error InvalidAsset();

    /**
     * @notice Custom error for invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Custom error for already claimed rewards
     */
    error AlreadyClaimed(uint64 startEpoch, uint64 endEpoch, address account);

    /**
     * @notice Custom error for invalid proof
     */
    error InvalidProof();
}
