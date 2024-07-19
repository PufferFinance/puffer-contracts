// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title L2RewardManagerStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract L2RewardManagerStorage {
    /**
     * @custom:storage-location erc7201:L2RewardManager.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */

    struct RateAndRoot {
        uint128 ethToPufETHRate;
        bytes32 rewardRoot;
    }

    struct RewardManagerStorage {
        /**
         * @notice Mapping to track the exchange rate from ETH to pufETH and reward root for each unique epoch range
         */
        mapping(uint64 startEpoch => mapping(uint64 endEpoch => RateAndRoot)) rateAndRoots;
        /**
         * @notice Mapping to track claimed tokens for users for each unique epoch range
         */
        mapping(uint64 startEpoch => mapping(uint64 endEpoch => mapping(address account => bool claimed))) claimedRewards;
        /**
         * @notice Mapping to track the custom claimer set by specific accounts
         */
        mapping(address account => address claimer) customClaimers;
    }

    // keccak256(abi.encode(uint256(keccak256("L2RewardManager.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _REWARD_MANAGER_STORAGE_LOCATION =
        0x7f1aa0bc41c09fbe61ccc14f95edc9998b7136087969b5ccb26131ec2cbbc800;

    function _getRewardManagerStorage()
        internal
        pure
        returns (RewardManagerStorage storage $)
    {
        // solhint-disable-next-line
        assembly {
            $.slot := _REWARD_MANAGER_STORAGE_LOCATION
        }
    }
}
