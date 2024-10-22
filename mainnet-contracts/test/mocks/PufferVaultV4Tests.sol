// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV4 } from "src/PufferVaultV4.sol";
import { IStETH } from "src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IEigenLayer } from "src/interface/EigenLayer/IEigenLayer.sol";
import { IStrategy } from "src/interface/EigenLayer/IStrategy.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";
import { IPufferOracle } from "src/interface/IPufferOracle.sol";
import { IDelegationManager } from "src/interface/EigenLayer/IDelegationManager.sol";
import { IPufferRestakingRewardsDepositor } from "src/interface/IPufferRestakingRewardsDepositor.sol";

contract PufferVaultV4Tests is PufferVaultV4 {
    constructor(
        IStETH stETH,
        IWETH weth,
        ILidoWithdrawalQueue lidoWithdrawalQueue,
        IStrategy stETHStrategy,
        IEigenLayer eigenStrategyManager,
        IPufferOracle oracle,
        IDelegationManager delegationManager,
        IPufferRestakingRewardsDepositor restakingRewardsDepositor
    )
        PufferVaultV4(
            stETH,
            weth,
            lidoWithdrawalQueue,
            stETHStrategy,
            eigenStrategyManager,
            oracle,
            delegationManager,
            restakingRewardsDepositor
        )
    {
        _disableInitializers();
    }

    // This functionality must be disabled because of the foundry tests
    modifier markDeposit() virtual override {
        _;
    }
}
