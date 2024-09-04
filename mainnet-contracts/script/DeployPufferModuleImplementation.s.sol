// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { PufferModule } from "../src/PufferModule.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IRewardsCoordinator } from "../src/interface/EigenLayer/IRewardsCoordinator.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";

/**
 * use --account of --private-key of the deployer to deploy
 * forge script script/DeployPufferModuleImplementation.s.sol:DeployPufferModuleImplementation --rpc-url=$RPC_URL --verify --broadcast -vvvv
 */
contract DeployPufferModuleImplementation is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        PufferModule newImpl = new PufferModule({
            protocol: PufferProtocol(_getPufferProtocol()),
            eigenPodManager: _getEigenPodManager(),
            delegationManager: IDelegationManager(_getDelegationManager()),
            moduleManager: PufferModuleManager(payable(_getPufferModuleManager())),
            rewardsCoordinator: IRewardsCoordinator(_getRewardsCoordinator())
        });

        vm.label(address(newImpl), "PufferModuleImplementation");

        bytes memory cd = abi.encodeCall(UpgradeableBeacon.upgradeTo, address(newImpl));

        bytes memory calldataToExecute = abi.encodeCall(AccessManager.execute, (_getPufferModuleBeacon(), cd));

        console.log("From Timelock queue a tx to accessManager");
        console.logBytes(calldataToExecute);

        if (block.chainid == holesky) {
            AccessManager(_getAccessManager()).execute(_getPufferModuleBeacon(), cd);
        }
    }
}
