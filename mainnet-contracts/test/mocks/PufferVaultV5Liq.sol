// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV5 } from "src/PufferVaultV5.sol";
import { IStETH } from "src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";
import { IPufferOracleV2 } from "src/interface/IPufferOracleV2.sol";
import { IPufferRevenueDepositor } from "src/interface/IPufferRevenueDepositor.sol";

contract PufferVaultV5Liq is PufferVaultV5 {
    uint256 private _lockedLiquidity;

    constructor(
        IStETH stETH,
        IWETH weth,
        ILidoWithdrawalQueue lidoWithdrawalQueue,
        IPufferOracleV2 oracle,
        IPufferRevenueDepositor revenueDepositor
    ) PufferVaultV5(stETH, lidoWithdrawalQueue, weth, oracle, revenueDepositor) {
        _disableInitializers();
    }

    // This functionality must be disabled because of the foundry tests
    modifier markDeposit() virtual override {
        _;
    }

    function reduceLiquidity(uint256 amount) external {
        _lockedLiquidity = amount;
        payable(msg.sender).transfer(amount);
    }

    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() + _lockedLiquidity;
    }
}
