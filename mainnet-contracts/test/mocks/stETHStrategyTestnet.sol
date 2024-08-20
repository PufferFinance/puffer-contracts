// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IStrategy } from "../../src/interface/EigenLayer/IStrategy.sol";

contract stETHStrategyTestnet is IStrategy {
    /**
     * @notice Returns the amount of underlying tokens for `user`
     */
    function userUnderlying(address) external pure returns (uint256) {
        return 0;
    }

    function userUnderlyingView(address) external pure returns (uint256) {
        return 0;
    }

    function sharesToUnderlyingView(uint256) external pure returns (uint256) {
        return 0;
    }
}
