// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { AVSContractsRegistry } from "../src/AVSContractsRegistry.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @dev This script is used to upgrade PufferModuleManager on Holesky
 *         forge script script/UpgradePufferModuleManager.s.sol:UpgradePufferModuleManager -vvvv --rpc-url=$RPC_URL --broadcast --verify
 */
contract UpgradePufferModuleManager is Script {
    address pufferModuleBeacon = address(0x4B0542470935ed4b085C3AD1983E85f5623ABf89);
    address restakingOperatorBeacon = address(0x99c3E46E575df251149866285DdA7DAEba875B71);
    PufferProtocol pufferProtocol = PufferProtocol(0xE00c79408B9De5BaD2FDEbB1688997a68eC988CD);
    AVSContractsRegistry avsContractsRegistry = AVSContractsRegistry(0x09BE86B01c1e32dCa2ebdEDb01cD5A3F798b80C5);
    address ACCESS_MANAGER = 0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e;
    address PufferModuleManagerProxy = 0x20377c306451140119C9967Ba6D0158a05b4eD07;

    function run() public {
        require(block.chainid == 17000, "This script is only for Holesky testnet");

        vm.startBroadcast();

        PufferModuleManager newImplementation = new PufferModuleManager({
            pufferModuleBeacon: address(pufferModuleBeacon),
            restakingOperatorBeacon: address(restakingOperatorBeacon),
            pufferProtocol: address(pufferProtocol),
            avsContractsRegistry: avsContractsRegistry
        });
        console.log("newImplementation", address(newImplementation));

        UUPSUpgradeable(PufferModuleManagerProxy).upgradeToAndCall(address(newImplementation), "");
    }
}
