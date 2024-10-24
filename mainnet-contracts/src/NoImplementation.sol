// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Unauthorized } from "./Errors.sol";

contract NoImplementation is UUPSUpgradeable {
    address public immutable UPGRADER;

    constructor() {
        UPGRADER = msg.sender;
    }

    function _authorizeUpgrade(address) internal virtual override {
        require(msg.sender == UPGRADER, Unauthorized());
    }
}
