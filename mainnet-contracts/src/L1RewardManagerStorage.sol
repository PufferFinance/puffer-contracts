// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title L1RewardManagerStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract L1RewardManagerStorage {
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
     * @notice Data required for bridging.
     * @param destinationDomainId The destination domain ID.
     */
    struct BridgeData {
        // using struct to allow future addition to this
        uint32 destinationDomainId;
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
        mapping(address bridge => BridgeData bridgeData) bridges;
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
