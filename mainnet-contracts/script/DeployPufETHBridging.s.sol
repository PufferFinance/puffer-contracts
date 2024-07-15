// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { BaseScript } from ".//BaseScript.s.sol";
import { PufferVault } from "../src/PufferVault.sol";
import { PufferVaultV3 } from "../src/PufferVaultV3.sol";
import { PufferVaultV2 } from "../src/PufferVaultV2.sol";

import { PufferVaultV3Tests } from "../src/PufferVaultV3Tests.sol";
import { IEigenLayer } from "../src/interface/EigenLayer/IEigenLayer.sol";
import { IStrategy } from "../src/interface/EigenLayer/IStrategy.sol";
import { IDelegationManager } from "../src/interface/EigenLayer/IDelegationManager.sol";
import { IStETH } from "../src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { LidoWithdrawalQueueMock } from "../test/mocks/LidoWithdrawalQueueMock.sol";
import { stETHStrategyMock } from "../test/mocks/stETHStrategyMock.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IWETH } from "../src/interface/Other/IWETH.sol";
import { IPufferOracle } from "../src/interface/IPufferOracle.sol";
import { IPufferVaultV3 } from "../src/interface/IPufferVaultV3.sol";

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PufferDeployment } from "../src/structs/PufferDeployment.sol";
import { PufferProtocolDeployment, BridgingDeployment } from "./DeploymentStructs.sol";

import { xPufETH } from "src/l2/xPufETH.sol";
import { XERC20Lockbox } from "src/XERC20Lockbox.sol";
import { ConnextMock } from "../test/mocks/ConnextMock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPufETHBridging
 * @author Puffer Finance
 * @notice Upgrades PufETH
 * @dev
 *
 *
 *         NOTE:
 *
 *         If you ran the deployment script, but did not `--broadcast` the transaction, it will still update your local chainId-deployment.json file.
 *         Other scripts will fail because addresses will be updated in deployments file, but the deployment never happened.
 *
 *         BaseScript.sol holds the private key logic, if you don't have `PK` ENV variable, it will use the default one PK from `makeAddr("pufferDeployer")`
 *
 *         PK=${deployer_pk} forge script script/DeployPufETHBridging.s.sol:DeployPufETHBridging --sig 'run(address)' "VAULTADDRESS" -vvvv --rpc-url=... --broadcast
 */
contract DeployPufETHBridging is BaseScript {
    function run(PufferDeployment memory deployment)
        public
        broadcast
        returns (BridgingDeployment memory bridgingDeployment)
    {
        //@todo this is for tests only
        AccessManager(deployment.accessManager).grantRole(1, _broadcaster, 0);

        xPufETH xpufETHImplementation = new xPufETH();

        xPufETH xPufETHProxy = xPufETH(
            address(
                new ERC1967Proxy{ salt: bytes32("xPufETH") }(
                    address(xpufETHImplementation), abi.encodeCall(xPufETH.initialize, (deployment.accessManager))
                )
            )
        );

        // Deploy the lockbox
        XERC20Lockbox xERC20Lockbox =
            new XERC20Lockbox({ xerc20: address(xPufETHProxy), erc20: deployment.pufferVault });

        bridgingDeployment = BridgingDeployment({
            connext: address(new ConnextMock()),
            xPufETH: address(xPufETHProxy),
            xPufETHLockBox: address(xERC20Lockbox)
        });
    }
}
