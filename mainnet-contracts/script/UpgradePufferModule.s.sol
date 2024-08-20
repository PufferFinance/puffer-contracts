// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { PufferModule } from "../src/PufferModule.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { IRewardsCoordinator } from "../src/interface/EigenLayer/IRewardsCoordinator.sol";

/**
 * @title UpgradePufferModule
 * @author Puffer Finance
 * @notice Upgrades PufferModuleManager
 * @dev
 *
 *         NOTE:
 *
 *         If you ran the deployment script, but did not `--broadcast` the transaction, it will still update your local chainId-deployment.json file.
 *         Other scripts will fail because addresses will be updated in deployments file, but the deployment never happened.
 *
 *         BaseScript.sol holds the private key logic, if you don't have `PK` ENV variable, it will use the default one PK from `makeAddr("pufferDeployer")`
 *
 *         PK=${deployer_pk} forge script script/UpgradePufferModule.s.sol:UpgradePufferModule -vvvv --rpc-url=$RPC_URL --account puffer --broadcast
 */
contract UpgradePufferModule is BaseScript {
    PufferProtocol pufferProtocol = PufferProtocol(payable(0xE00c79408B9De5BaD2FDEbB1688997a68eC988CD));
    address ACCESS_MANAGER = 0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e;
    address PUFFER_MODULE_BEACON = 0x4B0542470935ed4b085C3AD1983E85f5623ABf89;
    PufferModuleManager pufferModuleManager = PufferModuleManager(payable(0x20377c306451140119C9967Ba6D0158a05b4eD07));
    address eigenPodManager = 0x30770d7E3e71112d7A6b7259542D1f680a70e315;
    IDelegationManager delegationManager = IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7);
    IRewardsCoordinator rewardsCoordinator = IRewardsCoordinator(address(0));

    function run() public broadcast {
        require(block.chainid == 17000, "This script is only for Holesky testnet");
        PufferModule newImplementation = new PufferModule({
            protocol: pufferProtocol,
            eigenPodManager: eigenPodManager,
            delegationManager: delegationManager,
            moduleManager: pufferModuleManager,
            rewardsCoordinator: rewardsCoordinator
        });
        console.log("newImplementation", address(newImplementation));

        bytes memory calldataForAM = abi.encodeCall(UpgradeableBeacon.upgradeTo, address(newImplementation));

        console.logBytes(calldataForAM);
        AccessManager(ACCESS_MANAGER).execute(PUFFER_MODULE_BEACON, calldataForAM);
    }
}
