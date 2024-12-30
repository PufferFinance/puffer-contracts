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
import { IStrategy } from "src/interface/EigenLayer/IStrategy.sol";
import { IEigenLayer } from "src/interface/EigenLayer/IEigenLayer.sol";
import { IPufferOracle } from "src/interface/IPufferOracle.sol";
import { IDelegationManager } from "src/interface/EigenLayer/IDelegationManager.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title UpgradePufferVaultV3
 * 
 * @dev Use either --account (keystore) or --private-key (env)
 *
 * forge script ./script/UpgradePufferVaultV3.s.sol:UpgradePufferVaultV3
 *     --rpc-url $RPC_URL \
 *     --verify \
 *     --verifier-url if deploying on tenderly \
 *     --etherscan-api-key $TENDERLY_ACCESS_KEY or $ETHERSCAN_API_KEY \
 *     --broadcast \
 *     --slow
 */
contract UpgradePufferVaultV3 is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        PufferVaultV3 pufferVaultV3Implementation = new PufferVaultV3({
            stETH: IStETH(_getStETH()),
            weth: IWETH(_getWETH()),
            lidoWithdrawalQueue: ILidoWithdrawalQueue(_getLidoWithdrawalQueue()),
            stETHStrategy: IStrategy(_getStETHStrategy()),
            eigenStrategyManager: IEigenLayer(_getEigenLayerStrategyManager()),
            oracle: IPufferOracle(_getPufferOracle()),
            delegationManager: IDelegationManager(_getEigenDelegationManager()),
            maxGrantAmount: 1 ether,
            grantEpochStartTime: block.timestamp,
            grantEpochDuration: 30 days
        });

        _consoleLogOrUpgradeUUPS({
            proxyTarget: _getPufferVault(),
            implementation: address(pufferVaultV3Implementation),
            data: "",
            contractName: "PufferVaultV3Implementation"
        });

        vm.stopBroadcast();
    }
}
