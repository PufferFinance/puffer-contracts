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

/**
 * forge script script/DeployPufferModuleImplementation.s.sol:DeployPufferModuleImplementation --rpc-url=$RPC_URL --private-key $PK --verify --broadcast
 */
contract DeployPufferModuleImplementation is Script {
    address ACCESS_MANAGER = 0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e;
    address PUFFER_MODULE_BEACON = 0x4B0542470935ed4b085C3AD1983E85f5623ABf89;

    function run() public {
        require(block.chainid == 17000, "This script is only for Puffer Holesky testnet");

        vm.startBroadcast();

        PufferModule newImpl = new PufferModule({
            protocol: PufferProtocol(payable(0xE00c79408B9De5BaD2FDEbB1688997a68eC988CD)),
            eigenPodManager: 0x30770d7E3e71112d7A6b7259542D1f680a70e315,
            delegationManager: IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7),
            moduleManager: PufferModuleManager(0x20377c306451140119C9967Ba6D0158a05b4eD07),
            rewardsCoordinator: IRewardsCoordinator(0xAcc1fb458a1317E886dB376Fc8141540537E68fE)
        });

        bytes memory cd = abi.encodeCall(UpgradeableBeacon.upgradeTo, address(newImpl));

        // AccessManager is the owner of upgradeable beacon for restaking operator
        AccessManager(ACCESS_MANAGER).execute(PUFFER_MODULE_BEACON, cd);
    }
}
