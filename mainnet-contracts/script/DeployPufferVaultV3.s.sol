// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PufferVaultV3 } from "../src/PufferVaultV3.sol";
import { PufferVaultV3 } from "src/PufferVaultV3.sol";
import { IStETH } from "src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";
import { IPufferOracle } from "src/interface/IPufferOracle.sol";

/**
 * @title DeployPufferVaultV3
 * @dev
 *
 * use either --account (keystore) or --private-key (env)
 *
 * forge script ./script/DeployPufferVaultV3.s.sol:DeployPufferVaultV3 --force --rpc-url $RPC_URL \
 *     --verify \
 *     --verifier-url if deploying on tenderly \
 *     --etherscan-api-key $TENDERLY_ACCESS_KEY or $ETHERSCAN_API_KEY \
 *     --broadcast
 */
contract DeployPufferVaultV3 is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        PufferVaultV3 pufferVaultV3Implementation = new PufferVaultV3({
            stETH: IStETH(_getStETH()),
            weth: IWETH(_getWETH()),
            lidoWithdrawalQueue: ILidoWithdrawalQueue(_getLidoWithdrawalQueue()),
            oracle: IPufferOracle(_getPufferOracle())
        });

        //@todo Double check reinitialization
        _consoleLogOrUpgradeUUPS({
            proxyTarget: _getPufferVault(),
            implementation: address(pufferVaultV3Implementation),
            data: "",
            contractName: "PufferVaultV3Implementation"
        });
    }
}
