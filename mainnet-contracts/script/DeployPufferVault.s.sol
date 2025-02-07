// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PufferVaultV4 } from "../src/PufferVaultV4.sol";
import { IStETH } from "../src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "../src/interface/Other/IWETH.sol";
import { IStrategy } from "../src/interface/EigenLayer/IStrategy.sol";
import { IEigenLayer } from "../src/interface/EigenLayer/IEigenLayer.sol";
import { IPufferOracle } from "../src/interface/IPufferOracle.sol";
import { IDelegationManager } from "../src/interface/EigenLayer/IDelegationManager.sol";
import { IPufferRevenueDepositor } from "../src/interface/IPufferRevenueDepositor.sol";

/**
 * @title DeployPufferVault
 * @dev
 *
 * use either --account (keystore) or --private-key (env)
 *
 * forge script ./script/DeployPufferVault.s.sol:DeployPufferVault --force --rpc-url $RPC_URL \
 *     --verify \
 *     --verifier-url if deploying on tenderly \
 *     --etherscan-api-key $TENDERLY_ACCESS_KEY or $ETHERSCAN_API_KEY \
 *     --broadcast
 */
contract DeployPufferVault is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        PufferVaultV4 pufferVaultV4Implementation = new PufferVaultV4({
            stETH: IStETH(_getStETH()),
            weth: IWETH(_getWETH()),
            lidoWithdrawalQueue: ILidoWithdrawalQueue(_getLidoWithdrawalQueue()),
            stETHStrategy: IStrategy(_getStETHStrategy()),
            eigenStrategyManager: IEigenLayer(_getEigenLayerStrategyManager()),
            oracle: IPufferOracle(_getPufferOracle()),
            delegationManager: IDelegationManager(_getEigenDelegationManager()),
            revenueDepositor: IPufferRevenueDepositor(_getRevenueDepositor())
        });

        //@todo Double check reinitialization
        _consoleLogOrUpgradeUUPS({
            proxyTarget: _getPufferVault(),
            implementation: address(pufferVaultV4Implementation),
            data: "",
            contractName: "PufferVaultV4Implementation"
        });
    }
}
