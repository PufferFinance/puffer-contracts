// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { AVSContractsRegistry } from "../../src/AVSContractsRegistry.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { GenerateAccessManagerCalldata2 } from "script/AccessManagerMigrations/GenerateAccessManagerCalldata2.s.sol";

/**
 *     Use either -account or --private-key to sign the transaction
 *
 * To run the simulation run:
 *    forge script script/MainnetContractMigrations/UpgradePufferModuleManager.s.sol:UpgradePufferModuleManager -vvvv --rpc-url=$RPC_URL
 *
 * To run the deployment add --broadcast --verify
 */
contract UpgradePufferModuleManager is Script {
    address pufferModuleBeacon = address(0xdd38A5a7789C74fc7F64556fc772343658EEBb04);
    address restakingOperatorBeacon = address(0x6756B856Dd3843C84249a6A31850cB56dB824c4B);
    PufferProtocol pufferProtocol = PufferProtocol(0xf7b6B32492c2e13799D921E84202450131bd238B);
    AVSContractsRegistry avsContractsRegistry = AVSContractsRegistry(0x1565E55B63675c703fcC3778BD33eA97F7bE882F);
    address ACCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;
    address PufferModuleManagerProxy = 0x9E1E4fCb49931df5743e659ad910d331735C3860;

    function run() public {
        require(block.chainid == 1, "This script is only for Puffer mainnet");
        vm.startBroadcast();

        PufferModuleManager newImplementation = new PufferModuleManager({
            pufferModuleBeacon: address(pufferModuleBeacon),
            restakingOperatorBeacon: address(restakingOperatorBeacon),
            pufferProtocol: address(pufferProtocol),
            avsContractsRegistry: avsContractsRegistry
        });
        console.log("newImplementation", address(newImplementation));

        bytes memory calldataForAM = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newImplementation), ""));
        console.logBytes(calldataForAM);

        bytes memory calldataToExecute =
            abi.encodeCall(AccessManager.execute, (PufferModuleManagerProxy, calldataForAM));

        bytes memory cd = new GenerateAccessManagerCalldata2().run(PufferModuleManagerProxy);

        console.log("From Timelock queue a tx to accessManager");
        console.logBytes(calldataToExecute);

        console.log("From Timelock queue a tx to accessManager");
        console.logBytes(cd);
    }
}
