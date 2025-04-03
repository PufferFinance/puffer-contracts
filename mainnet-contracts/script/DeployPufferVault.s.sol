// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PufferVaultV5 } from "../src/PufferVaultV5.sol";
import { IStETH } from "../src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "../src/interface/Other/IWETH.sol";
import { IStrategy } from "../src/interface/Eigenlayer-Slashing/IStrategy.sol";
import { IEigenLayer } from "../src/interface/Eigenlayer-Slashing/IEigenLayer.sol";
import { IPufferOracleV2 } from "../src/interface/IPufferOracleV2.sol";
import { IDelegationManager } from "../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
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

        PufferVaultV5 PufferVaultV5Implementation = new PufferVaultV5({
            stETH: IStETH(_getStETH()),
            lidoWithdrawalQueue: ILidoWithdrawalQueue(_getLidoWithdrawalQueue()),
            weth: IWETH(_getWETH()),
            pufferOracle: IPufferOracleV2(_getPufferOracle()),
            revenueDepositor: IPufferRevenueDepositor(_getRevenueDepositor())
        });

        //@todo Double check reinitialization
        _consoleLogOrUpgradeUUPS({
            proxyTarget: _getPufferVault(),
            implementation: address(PufferVaultV5Implementation),
            data: "",
            contractName: "PufferVaultV5Implementation"
        });
    }
}
