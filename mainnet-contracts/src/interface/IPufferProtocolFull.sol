// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferProtocol } from "./IPufferProtocol.sol";
import { IPufferProtocolLogic } from "./IPufferProtocolLogic.sol";
import { IPufferProtocolEvents } from "./IPufferProtocolEvents.sol";

interface IPufferProtocolFull is IPufferProtocol, IPufferProtocolLogic, IPufferProtocolEvents {}
