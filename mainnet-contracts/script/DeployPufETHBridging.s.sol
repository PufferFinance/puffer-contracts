// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { BaseScript } from ".//BaseScript.s.sol";
import { PufferVault } from "../src/PufferVault.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PufferDeployment } from "../src/structs/PufferDeployment.sol";
import { BridgingDeployment } from "./DeploymentStructs.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { XPufETHBurner } from "src/XPufETHBurner.sol";
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

        // XPufETHBurner
        XPufETHBurner xPufETHBurnerImpl = new XPufETHBurner({
            XpufETH: address(xPufETHProxy),
            pufETH: deployment.pufferVault,
            lockbox: address(xERC20Lockbox),
            l2RewardsManager: makeAddr("l2RewardsManagerMock")
        });

        XPufETHBurner xPufETHBurnerProxy = XPufETHBurner(
            address(
                new ERC1967Proxy(
                    address(xPufETHBurnerImpl), abi.encodeCall(xPufETH.initialize, (deployment.accessManager))
                )
            )
        );

        bridgingDeployment = BridgingDeployment({
            connext: address(new ConnextMock()),
            xPufETH: address(xPufETHProxy),
            xPufETHLockBox: address(xERC20Lockbox),
            xPufETHBurner: address(xPufETHBurnerProxy)
        });
    }
}
