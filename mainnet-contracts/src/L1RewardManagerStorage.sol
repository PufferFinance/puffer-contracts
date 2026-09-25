// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title L1RewardManagerStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract L1RewardManagerStorage {
    /**
     * @notice The status of a rewards interval
     * @dev NONE: The interval does not exist
     *      ACTIVE: The rewards are minted. They can be claimed from `claimableAt`
     *      FROZEN: The claiming is stopped. The interval can only be reverted
     *      REVERTED: The minted pufETH is burned. The interval can not be claimed
     */
    enum IntervalStatus {
        NONE,
        ACTIVE,
        FROZEN,
        REVERTED
    }

    /**
     * @notice A record of one rewards interval
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param claimableAt The timestamp from which the rewards of this interval can be claimed
     * It is set when the interval is minted, so a later change of `claimingDelay` does not change it
     * @param pufETHAmount The pufETH amount minted for this interval
     * @param ethAmount The ETH amount of the rewards
     * @param claimedPufETHAmount The pufETH amount already paid out for this interval
     * It can never be higher than `pufETHAmount`
     * @param status The status of the interval
     * @param ethToPufETHRate The exchange rate from ETH to pufETH when the interval was minted
     * @param rewardsRoot The merkle root of the rewards
     */
    struct Interval {
        uint104 startEpoch; // slot 0
        uint104 endEpoch; // slot 0
        uint48 claimableAt; // slot 0
        uint128 pufETHAmount; // slot 1
        uint128 ethAmount; // slot 1
        uint128 claimedPufETHAmount; // slot 2
        IntervalStatus status; // slot 2
        uint256 ethToPufETHRate; // slot 3
        bytes32 rewardsRoot; // slot 4
    }

    /**
     * @custom:storage-location erc7201:l1rewardmanager.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct RewardManagerStorage {
        uint104 allowedRewardMintAmount;
        uint104 allowedRewardMintFrequency;
        uint48 lastRewardMintTimestamp;
        /**
         * @dev DEPRECATED: Unused bridge mapping, kept for storage layout compatibility
         */
        mapping(address bridge => uint32 deprecatedDestinationDomainId) _deprecatedBridges;
        /**
         * @dev DEPRECATED: The LayerZero destination endpoint ID from when the rewards were bridged to L2.
         * Kept for storage layout compatibility
         */
        uint32 _deprecatedDestinationEID;
        /**
         * @notice The last successfully processed interval end epoch
         */
        uint256 lastIntervalEndEpoch;
        /**
         * @notice The current interval end epoch being processed
         */
        uint256 currentIntervalEndEpoch;
        /**
         * @notice The delay between the minting of an interval and the start of its claiming
         * @dev During this delay a wrong interval can be frozen and reverted
         */
        uint256 claimingDelay;
        /**
         * @notice The ID of the newest minted interval
         * @dev Only this interval can be frozen and reverted
         */
        bytes32 newestIntervalId;
        /**
         * @notice The rewards intervals
         * @dev `intervalId` is `keccak256(abi.encodePacked(startEpoch, endEpoch))`
         */
        mapping(bytes32 intervalId => Interval) intervals;
        /**
         * @notice Tracks which accounts already claimed the rewards of an interval
         */
        mapping(bytes32 intervalId => mapping(address account => bool claimed)) claimedRewards;
    }

    // keccak256(abi.encode(uint256(keccak256("l1rewardmanager.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _REWARD_MANAGER_STORAGE_LOCATION =
        0xb18045c429f6c4e33b477568e1a40f795629ac8937518d2b48a302e4c0fbb700;

    function _getRewardManagerStorage() internal pure returns (RewardManagerStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _REWARD_MANAGER_STORAGE_LOCATION
        }
    }
}
