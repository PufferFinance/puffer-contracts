// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV2 } from "src/PufferVaultV2.sol";
import { IStETH } from "src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IEigenLayer } from "src/interface/EigenLayer/IEigenLayer.sol";
import { IStrategy } from "src/interface/EigenLayer/IStrategy.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";
import { IPufferOracle } from "src/interface/IPufferOracle.sol";
import { IDelegationManager } from "src/interface/EigenLayer/IDelegationManager.sol";

contract PufferVaultV2Tests is PufferVaultV2 {
    constructor(
        IStETH stETH,
        IWETH weth,
        ILidoWithdrawalQueue lidoWithdrawalQueue,
        IStrategy stETHStrategy,
        IEigenLayer eigenStrategyManager,
        IPufferOracle oracle,
        IDelegationManager delegationManager
    ) PufferVaultV2(stETH, weth, lidoWithdrawalQueue, stETHStrategy, eigenStrategyManager, oracle, delegationManager) {
        _WETH = weth;
        PUFFER_ORACLE = oracle;
        _disableInitializers();
    }

    // This functionality must be disabled because of the foundry tests
    modifier markDeposit() virtual override {
        _;
    }
}
