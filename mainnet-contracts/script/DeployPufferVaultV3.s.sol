// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { console } from "forge-std/console.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PufferVault } from "src/PufferVault.sol";
import { PufferVaultV3 } from "src/PufferVaultV3.sol";
import { IStETH } from "src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";
import { IStrategy } from "src/interface/EigenLayer/IStrategy.sol";
import { IEigenLayer } from "src/interface/EigenLayer/IEigenLayer.sol";
import { IPufferOracle } from "src/interface/IPufferOracle.sol";
import { IDelegationManager } from "src/interface/EigenLayer/IDelegationManager.sol";

/**
 * @title DeployPufferVaultV3
 * 
 * @dev Use either --account (keystore) or --private-key (env)
 * forge script ./script/DeployPufferVaultV3.s.sol:DeployPufferVaultV3 \
 *     --rpc-url $RPC_URL \
 *     --verify \
 *     --verifier-url if deploying on tenderly \
 *     --etherscan-api-key $TENDERLY_ACCESS_KEY or $ETHERSCAN_API_KEY \
 *     --broadcast \
 *     --slow
 */
contract DeployPufferVaultV3 is DeployerHelper {
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
        console.log("PufferVaultV3 Implementation: %s", address(pufferVaultV3Implementation));

        ERC1967Proxy pufferVaultProxy = new ERC1967Proxy{ salt: bytes32("PufferVaultV3") }(
            address(pufferVaultV3Implementation), abi.encodeCall(PufferVault.initialize, (_getAccessManager()))
        );
        console.log("PufferVaultV3 Proxy: %s", address(pufferVaultProxy));

        vm.stopBroadcast();
    }
}
