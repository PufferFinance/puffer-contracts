// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title PufferRestakingRewardsDepositorStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract PufferRestakingRewardsDepositorStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @custom:storage-location erc7201:RestakingRewardsDepositor.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct RestakingRewardsDepositorStorage {
        /**
         * @notice Restaking operators.
         */
        EnumerableSet.AddressSet restakingOperators;
        /**
         * @notice RNO rewards in bps.
         */
        uint128 rNORewardsBps;
        /**
         * @notice Treasury rewards in bps.
         */
        uint128 treasuryRewardsBps;
        /**
         * @notice Last deposit timestamp.
         */
        uint48 lastDepositTimestamp;
        /**
         * @notice Rewards distribution window.
         */
        uint104 rewardsDistributionWindow;
        /**
         * @notice Last deposit amount.
         */
        uint104 lastDepositAmount;
    }

    /**
     * @dev Storage slot location for RestakingRewardsDepositorStorage
     * @custom:storage-location erc7201:RestakingRewardsDepositor.storage
     * keccak256(abi.encode(uint256(keccak256("RestakingRewardsDepositor.storage")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant _RESTAKE_REWARDS_DEPOSITOR_STORAGE =
        0xf06bc84d5dffe01f6559e934f5a062e2abca02c8f0e842bc9b567621039cd300;

    function _getRestakingRewardsDepositorStorage()
        internal
        pure
        returns (RestakingRewardsDepositorStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _RESTAKE_REWARDS_DEPOSITOR_STORAGE
        }
    }
}
