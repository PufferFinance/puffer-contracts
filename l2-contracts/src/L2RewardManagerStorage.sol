// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IL2RewardManager } from "./interface/IL2RewardManager.sol";

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
    struct RewardManagerStorage {
        /**
         * @notice Mapping to track the exchange rate from ETH to pufETH and reward root for each unique epoch range
         * @dev `rewardsInterval` is calculated as `keccak256(abi.encodePacked(startEpoch, endEpoch))`
         * we are using that instead of the merkle root, because we want to prevent double posting of the same epoch range
         */
        mapping(bytes32 rewardsInterval => IL2RewardManager.EpochRecord) epochRecords;
        /**
         * @notice Mapping to track claimed tokens for users for each unique epoch range
         * @dev `rewardsInterval` is calculated as `keccak256(abi.encodePacked(startEpoch, endEpoch))`
         * we are using that instead of the merkle root, because we want to prevent double posting of the same epoch range
         */
        mapping(bytes32 rewardsInterval => mapping(address account => bool claimed)) claimedRewards;
        /**
         * @notice Mapping to track the custom claimer set by specific accounts
         */
        mapping(address account => address claimer) rewardsClaimers;
        /**
         * @notice This period is used to delay the rewards claim for the users
         * After the rewards have been bridged from L1, we will wait for this period before allowing the users to claim the rewards for that rewards interval
         */
        uint256 claimingDelay;
    }

    // keccak256(abi.encode(uint256(keccak256("L2RewardManager.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _REWARD_MANAGER_STORAGE_LOCATION =
        0x7f1aa0bc41c09fbe61ccc14f95edc9998b7136087969b5ccb26131ec2cbbc800;

    function _getRewardManagerStorage() internal pure returns (RewardManagerStorage storage $) {
        // solhint-disable-next-line
        assembly {
            $.slot := _REWARD_MANAGER_STORAGE_LOCATION
        }
    }
}
