// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV5 } from "src/PufferVaultV5.sol";
import { IStETH } from "src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";
import { IPufferOracleV2 } from "src/interface/IPufferOracleV2.sol";
import { IPufferRevenueDepositor } from "src/interface/IPufferRevenueDepositor.sol";
import { IPermissionedOracle } from "src/interface/IPermissionedOracle.sol";

contract PufferVaultV5Tests is PufferVaultV5 {
    constructor(
        IStETH stETH,
        IWETH weth,
        ILidoWithdrawalQueue lidoWithdrawalQueue,
        IPufferOracleV2 oracle,
        IPufferRevenueDepositor revenueDepositor,
        IPermissionedOracle permissionedOracle
    ) PufferVaultV5(stETH, lidoWithdrawalQueue, weth, oracle, revenueDepositor, permissionedOracle) {
        _disableInitializers();
    }

    // This functionality must be disabled because of the foundry tests
    modifier markDeposit() virtual override {
        _;
    }
}
