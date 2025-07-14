// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferProtocol } from "./IPufferProtocol.sol";
import { IPufferProtocolLogic } from "./IPufferProtocolLogic.sol";
import { IPufferProtocolEvents } from "./IPufferProtocolEvents.sol";
import { IPufferProtocolManagement } from "./IPufferProtocolManagement.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

interface IPufferProtocolFull is
    IPufferProtocol,
    IPufferProtocolLogic,
    IPufferProtocolEvents,
    IPufferProtocolManagement,
    IAccessManaged
{
    function nonces(bytes32 selector, address owner) external view returns (uint256);
}
