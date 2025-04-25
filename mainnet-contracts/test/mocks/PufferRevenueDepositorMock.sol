// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferRevenueDepositor } from "../../src/interface/IPufferRevenueDepositor.sol";

contract PufferRevenueDepositorMock is IPufferRevenueDepositor {

    function getPendingDistributionAmount()
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function getRewardsDistributionWindow()
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }
}
