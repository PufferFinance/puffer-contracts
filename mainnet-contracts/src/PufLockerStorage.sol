// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufLocker } from "./interface/IPufLocker.sol";

/**
 * @title PufLockerStorage
 * @author Puffer Finance
 * @dev Storage contract for PufLocker to support upgradability
 * @custom:security-contact security@puffer.fi
 */
abstract contract PufLockerStorage {
    // Storage slot location for PufLocker data

    // keccak256(abi.encode(uint256(keccak256("PufLocker.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PUF_LOCKER_STORAGE_SLOT =
        0xaf4bf4b31f04ca259733013a412d3e67552036ab2d2af267876ad7f9110e5d00;

    /// @custom:storage-location erc7201:PufLocker.storage
    struct PufLockerData {
        mapping(address token => bool isAllowed) allowedTokens;
        mapping(address depositor => mapping(address token => IPufLocker.Deposit[])) deposits;
        uint128 minLockPeriod;
        uint128 maxLockPeriod;
    }

    function _getPufLockerStorage() internal pure returns (PufLockerData storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _PUF_LOCKER_STORAGE_SLOT
        }
    }
}
