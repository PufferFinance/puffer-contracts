// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferProtocol } from "./IPufferProtocol.sol";
import { IPufferProtocolLogic } from "./IPufferProtocolLogic.sol";
import { IPufferProtocolEvents } from "./IPufferProtocolEvents.sol";
import { IPufferProtocolManagement } from "./IPufferProtocolManagement.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

/**
 * @title IPufferProtocolFull
 * @author Puffer Finance
 * @notice This interface contains all the functions and events of the Puffer Protocol and the PufferProtocolLogic contract
 * @dev This interface is used in tests and to use the whole Puffer Protocol in one contract
 */
interface IPufferProtocolFull is
    IPufferProtocol,
    IPufferProtocolLogic,
    IPufferProtocolEvents,
    IPufferProtocolManagement,
    IAccessManaged
{
    /**
     * @notice Returns the next unused nonce for an address in a specific function context.
     * @dev Check ProtocolSignatureNonces.sol for more details
     * @param selector The function selector that determines the nonce space
     * @param owner The address to get the nonce for
     * @return The current nonce value for the owner in the specified function context
     */
    function nonces(bytes32 selector, address owner) external view returns (uint256);
}
