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
import { IDelayedWithdrawalRouter } from "eigenlayer/interfaces/IDelayedWithdrawalRouter.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * forge script script/DeployPufferModuleImplementation.s.sol:DeployPufferModuleImplementation --rpc-url=$RPC_URL --private-key $PK
 */
contract DeployPufferModuleImplementation is Script {
    address ACCESS_MANAGER = 0xA6c916f85DAfeb6f726E03a1Ce8d08cf835138fF;
    address PUFFER_MODULE_BEACON = 0x5B81A4579f466fB17af4d8CC0ED51256b94c61D4;

    function run() public {
        require(block.chainid == 17000, "This script is only for Puffer Holesky testnet");

        vm.startBroadcast();

        PufferModule newImpl = new PufferModule({
            protocol: PufferProtocol(payable(0x705E27D6A6A0c77081D32C07DbDE5A1E139D3F14)),
            eigenPodManager: 0x30770d7E3e71112d7A6b7259542D1f680a70e315,
            eigenWithdrawalRouter: IDelayedWithdrawalRouter(0x642c646053eaf2254f088e9019ACD73d9AE0FA32),
            delegationManager: IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7),
            moduleManager: PufferModuleManager(0xe4695ab93163F91665Ce5b96527408336f070a71)
        });

        bytes memory cd = abi.encodeCall(UpgradeableBeacon.upgradeTo, address(newImpl));

        // AccessManager is the owner of upgradeable beacon for restaking operator
        AccessManager(ACCESS_MANAGER).execute(PUFFER_MODULE_BEACON, cd);
    }
}
