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
import { L1RewardManager } from "src/L1RewardManager.sol";
import { XERC20Lockbox } from "src/XERC20Lockbox.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { NoImplementation } from "../src/NoImplementation.sol";
import { ConnextMock } from "../test/mocks/ConnextMock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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

        address everclearBridge = address(new ConnextMock());

        address noImpl = address(new NoImplementation());

        ERC1967Proxy l2RewardsManagerProxy = new ERC1967Proxy(noImpl, "");

        // Deploy the lockbox
        XERC20Lockbox xERC20Lockbox =
            new XERC20Lockbox({ xerc20: address(xPufETHProxy), erc20: deployment.pufferVault });

        // L1RewardManager
        L1RewardManager l1RewardManagerImpl = new L1RewardManager({
            xPufETH: address(xPufETHProxy),
            pufETH: deployment.pufferVault,
            lockbox: address(xERC20Lockbox),
            l2RewardsManager: address(l2RewardsManagerProxy)
        });

        L1RewardManager l1RewardManagerProxy = L1RewardManager(
            address(
                new ERC1967Proxy(
                    address(l1RewardManagerImpl), abi.encodeCall(xPufETH.initialize, (deployment.accessManager))
                )
            )
        );

        L2RewardManager l2RewardManagerImpl = new L2RewardManager(everclearBridge, address(l1RewardManagerProxy));

        UUPSUpgradeable(address(l2RewardsManagerProxy)).upgradeToAndCall(
            address(l2RewardManagerImpl), abi.encodeCall(L2RewardManager.initialize, (deployment.accessManager))
        );

        bridgingDeployment = BridgingDeployment({
            connext: everclearBridge,
            xPufETH: address(xPufETHProxy),
            xPufETHLockBox: address(xERC20Lockbox),
            l1RewardManager: address(l1RewardManagerProxy),
            l2RewardManager: address(l2RewardsManagerProxy)
        });
    }
}
