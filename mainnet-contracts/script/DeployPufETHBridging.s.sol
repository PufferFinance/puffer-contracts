// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { BaseScript } from ".//BaseScript.s.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PufferDeployment } from "../src/structs/PufferDeployment.sol";
import { BridgingDeployment } from "./DeploymentStructs.sol";
import { L1RewardManager } from "src/L1RewardManager.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { NoImplementation } from "../src/NoImplementation.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { pufETHAdapter } from "partners-layerzero/contracts/pufETHAdapter.sol";
import { pufETH } from "partners-layerzero/contracts/pufETH.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { console } from "forge-std/console.sol";

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
    // Declaration of mock endpoint IDs.
    uint16 layerzeroL1Eid = 1;
    uint16 layerzeroL2Eid = 2;

    function run(PufferDeployment memory deployment)
        public
        broadcast
        returns (BridgingDeployment memory bridgingDeployment)
    {
        // console.log("address of _broadcaster", address(_broadcaster));
        // console.log("address this contract", address(this));
        // TestHelperOz5.setUp();
        // console.log("setup done 2");

        // Setup function to initialize 2 Mock Endpoints with Mock MessageLib.
        // setUpEndpoints(2, LibraryType.UltraLightNode);

        // address layerzeroL1EndpointAddress = endpoints[layerzeroL1Eid];
        address layerzeroL1EndpointAddress;
        address layerzeroL2EndpointAddress;
        // console.log("layerzeroL1EndpointAddress", layerzeroL1EndpointAddress);

        // address layerzeroL2EndpointAddress = endpoints[layerzeroL2Eid];
        // console.log("layerzeroL2EndpointAddress", layerzeroL2EndpointAddress);

        //@todo this is for tests only
        AccessManager(deployment.accessManager).grantRole(1, _broadcaster, 0);

        // xPufETH xpufETHImplementation = new xPufETH();

        // xPufETH xPufETHProxy = xPufETH(
        //     address(
        //         new ERC1967Proxy{ salt: bytes32("xPufETH") }(
        //             address(xpufETHImplementation), abi.encodeCall(xPufETH.initialize, (deployment.accessManager))
        //         )
        //     )
        // );

        // address everclearBridge = address(new ConnextMock());
        // address endpoint = 0x1a44076050125825900e736c501f859c50fE728c;

        // console.log("endpoint", endpoint);
        console.log("pufferVault", address(deployment.pufferVault));
        console.log("broadcaster", _broadcaster);

        pufETHAdapter pufETHOFTAdapter;
        // address[] memory sender = setupOApps(type(pufETHAdapter).creationCode, 1, 1);
        // pufETHOFTAdapter = pufETHAdapter(payable(sender[0]));
        console.log("pufETHOFTAdapter", address(pufETHOFTAdapter));

        pufETH pufETHOFT;
        // address[] memory sender2 = setupOApps(type(pufETH).creationCode, 1, 1);
        // pufETHOFT = pufETH(payable(sender2[0]));
        console.log("pufETHOFT", address(pufETHOFT));

        // we will generate it from the test helper of layerzero
        // console.log("pufETHOFTAdapter", pufETHOFTAdapter);
        // address pufETHOFT ;
        // console.log("pufETHOFT", pufETHOFT);

        // address noImpl = address(new NoImplementation());

        // ERC1967Proxy l2RewardsManagerProxy = new ERC1967Proxy(noImpl, "");

        // // // Deploy the lockbox
        // // XERC20Lockbox xERC20Lockbox =
        // //     new XERC20Lockbox({ xerc20: address(xPufETHProxy), erc20: deployment.pufferVault });

        // // L1RewardManager
        // L1RewardManager l1RewardManagerImpl = new L1RewardManager({
        //     oft: address(pufETHOFTAdapter),
        //     pufETH: deployment.pufferVault,
        //     l2RewardsManager: address(l2RewardsManagerProxy)
        // });

        // L1RewardManager l1RewardManagerProxy = L1RewardManager(
        //     address(
        //         new ERC1967Proxy(
        //             address(l1RewardManagerImpl), abi.encodeCall(L1RewardManager.initialize, (deployment.accessManager))
        //         )
        //     )
        // );

        // L2RewardManager l2RewardManagerImpl = new L2RewardManager(address(pufETHOFT), address(l1RewardManagerProxy));

        // UUPSUpgradeable(address(l2RewardsManagerProxy)).upgradeToAndCall(
        //     address(l2RewardManagerImpl), abi.encodeCall(L2RewardManager.initialize, (deployment.accessManager))
        // );

        bridgingDeployment = BridgingDeployment({
            pufETHOFTAdapter: address(pufETHOFTAdapter),
            pufETHOFT: address(pufETHOFT),
            l1RewardManager: address(0),
            l2RewardManager: address(0),
            layerzeroL1Endpoint: layerzeroL1EndpointAddress,
            layerzeroL2Endpoint: layerzeroL2EndpointAddress
        });
    }
}
