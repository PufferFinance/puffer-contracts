// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";

/**
 * forge script script/DeployPufferModuleManager.s.sol:DeployPufferModuleManager -vvvv --rpc-url=$RPC_URL --broadcast --verify
 */
contract DeployPufferModuleManager is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        _deploy();
    }

    function deployPufferModuleManagerTests() public returns (PufferModuleManager) {
        return _deploy();
    }

    function _deploy() internal returns (PufferModuleManager) {
        PufferModuleManager newPufferModuleManagerImplementation = new PufferModuleManager({
            pufferModuleBeacon: address(_getPufferModuleBeacon()),
            restakingOperatorBeacon: address(_getRestakingOperatorBeacon()),
            pufferProtocol: address(_getPufferProtocol())
        });

        _consoleLogOrUpgradeUUPSPrank({
            proxyTarget: _getPufferModuleManager(),
            implementation: address(newPufferModuleManagerImplementation),
            data: "",
            contractName: "PufferModuleManagerImplementation"
        });

        return newPufferModuleManagerImplementation;
    }
}
