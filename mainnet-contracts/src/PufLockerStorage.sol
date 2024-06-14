// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufLocker } from "./interface/IPufLocker.sol";

/**
 * @title PufLockerStorage
 * @dev Storage contract for PufLocker to support upgradability
 */
abstract contract PufLockerStorage {
    // Storage slot location for PufLocker data
    bytes32 private constant _PUF_LOCKER_STORAGE_SLOT =
        0xed4b58c94786491f32821dd56ebc03d5f67df2b901c79c3e972343a4fbb3dfed; // keccak256("PufLocker.storage");

    struct PufLockerData {
        mapping(address => bool) allowedTokens;
        mapping(address => mapping(address => IPufLocker.Deposit[])) deposits;
        uint40 minLockPeriod;
        uint40 maxLockPeriod;
    }

    function _getPufLockerStorage() internal pure returns (PufLockerData storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _PUF_LOCKER_STORAGE_SLOT
        }
    }
}
