// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { BaseScript } from "./BaseScript.s.sol";

/**
 * // Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/UpgradeXpufETH.s.sol:UpgradeXpufETH --rpc-url $RPC_URL --account puffer
 *
 *       forge cache clean
 *
 *       forge script script/UpgradeXpufETH.s.sol:UpgradeXpufETH --rpc-url $RPC_URL --account puffer --broadcast
 */
contract UpgradeXpufETH is BaseScript {
    address ACCCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;
    address XPUFETH_PROXY = 0xD7D2802f6b19843ac4DfE25022771FD83b5A7464;

    function run() public broadcast {
        xPufETH xpufETHImplementation = new xPufETH();

        bytes memory upgradeCalldata =
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, address(xpufETHImplementation), "");

        bytes memory timelockCalladata =
            abi.encodeWithSelector(AccessManager.execute.selector, XPUFETH_PROXY, upgradeCalldata);

        console.logBytes(timelockCalladata);

        console.log("xpufETH implementation:", address(xpufETHImplementation));
    }
}
