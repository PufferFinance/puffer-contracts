// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV2 } from "src/PufferVaultV2.sol";
import { IStETH } from "src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";
import { IPufferOracle } from "src/interface/IPufferOracle.sol";

contract PufferVaultV2Tests is PufferVaultV2 {
    constructor(IStETH stETH, IWETH weth, ILidoWithdrawalQueue lidoWithdrawalQueue, IPufferOracle oracle)
        PufferVaultV2(stETH, weth, lidoWithdrawalQueue, oracle)
    {
        _WETH = weth;
        PUFFER_ORACLE = oracle;
        _disableInitializers();
    }

    // This functionality must be disabled because of the foundry tests
    modifier markDeposit() virtual override {
        _;
    }
}
