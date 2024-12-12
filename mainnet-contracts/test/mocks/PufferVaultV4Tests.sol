// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV4 } from "src/PufferVaultV4.sol";
import { IStETH } from "src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IEigenLayer } from "src/interface/Eigenlayer-Slashing/IEigenLayer.sol";
import { IStrategy } from "src/interface/Eigenlayer-Slashing/IStrategy.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";
import { IPufferOracle } from "src/interface/IPufferOracle.sol";
import { IDelegationManager } from "src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IPufferRevenueDepositor } from "src/interface/IPufferRevenueDepositor.sol";

contract PufferVaultV4Tests is PufferVaultV4 {
    constructor(
        IStETH stETH,
        IWETH weth,
        ILidoWithdrawalQueue lidoWithdrawalQueue,
        IStrategy stETHStrategy,
        IEigenLayer eigenStrategyManager,
        IPufferOracle oracle,
        IDelegationManager delegationManager,
        IPufferRevenueDepositor revenueDepositor
    )
        PufferVaultV4(
            stETH,
            weth,
            lidoWithdrawalQueue,
            stETHStrategy,
            eigenStrategyManager,
            oracle,
            delegationManager,
            revenueDepositor
        )
    {
        _disableInitializers();
    }

    // This functionality must be disabled because of the foundry tests
    modifier markDeposit() virtual override {
        _;
    }
}
