// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Vesting } from "./struct/CarrotVestingStruct.sol";

/**
 * @title CarrotVestingStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract CarrotVestingStorage {
    /**
     * @custom:storage-location erc7201:carrotvesting.storage
     */
    struct VestingStorage {
        uint48 startTimestamp;
        uint32 duration;
        uint32 steps;
        bool isDismantled;
        uint128 totalDepositedAmount;
        mapping(address user => Vesting[] vestingInfo) vestings;
        uint48 upgradeTimestamp;
        uint32 newDuration;
        uint32 newSteps;
    }

    // keccak256(abi.encode(uint256(keccak256("carrotvesting.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _CARROT_VESTING_STORAGE_LOCATION =
        0x99c0204d2f19059e8c922c8f9e67431492b83efddf8cd154a45548a1cb00c300;

    function _getCarrotVestingStorage() internal pure returns (VestingStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _CARROT_VESTING_STORAGE_LOCATION
        }
    }
}
