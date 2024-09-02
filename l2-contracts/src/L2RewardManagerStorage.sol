// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title L2RewardManagerStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract L2RewardManagerStorage {
    /**
     * @notice A record of a single epoch for storing the rate and root.
     * @param startEpoch The start epoch of the interval
     * @param endEpoch The end epoch of the interval
     * @param ethToPufETHRate The exchange rate from ETH to pufETH.
     * @param rewardRoot The merkle root of the rewards.
     * @param timeBridged The timestamp of then the rewars were bridged to L2.
     * @param pufETHAmount The xPufETH amount minted and bridged.
     * @param ethAmount The ETH amount that was converted.
     *
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct EpochRecord {
        uint104 startEpoch; // packed slot 0
        uint104 endEpoch; // packed slot 0
        uint48 timeBridged; // packed slot 0
        uint128 pufETHAmount; // packed slot 1
        uint128 ethAmount; // packed slot 1
        uint256 ethToPufETHRate; // slot 2
        bytes32 rewardRoot;
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
        mapping(bytes32 rewardsInterval => EpochRecord) epochRecords;
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
         * @dev Mapping to track the bridge data for each bridge
         */
        mapping(address bridge => BridgeData bridgeData) bridges;
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
