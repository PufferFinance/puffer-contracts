// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title PufferRevenueDepositorStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract PufferRevenueDepositorStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @custom:storage-location erc7201:RevenueDepositor.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct RevenueDepositorStorage {
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
     * @dev Storage slot location for RevenueDepositorStorage
     * @custom:storage-location erc7201:RevenueDepositor.storage
     * keccak256(abi.encode(uint256(keccak256("RevenueDepositor.storage")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant _REVENUE_DEPOSITOR_STORAGE =
        0x4a89cef1c30d36c0ff2c9fb23c831a9c153cf25feb747c6591cde6a5261b4000;

    function _getRevenueDepositorStorage() internal pure returns (RevenueDepositorStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _REVENUE_DEPOSITOR_STORAGE
        }
    }
}
