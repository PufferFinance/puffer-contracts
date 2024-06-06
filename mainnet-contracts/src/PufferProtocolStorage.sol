// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ProtocolStorage } from "./struct/ProtocolStorage.sol";

/**
 * @title PufferProtocolStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract PufferProtocolStorage {
    /**
     * @dev Storage slot location for PufferProtocol
     * @custom:storage-location erc7201:PufferProtocol.storage
     */
    bytes32 private constant _PUFFER_PROTOCOL_STORAGE =
        0xb8d3716136db480afe9a80da6be84f994509ecf9515ed14d03024589b5f2bd00;

    function _getPufferProtocolStorage() internal pure returns (ProtocolStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _PUFFER_PROTOCOL_STORAGE
        }
    }
}
