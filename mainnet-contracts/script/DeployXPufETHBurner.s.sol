// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { XPufETHBurner } from "src/XPufETHBurner.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/DeployXPufETHBurner.s.sol:DeployXPufETHBurner -vvvv --rpc-url=...
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */
contract DeployXPufETHBurner is DeployerHelper {
    //@todo Update the address
    address L2_REWARDS_MANAGER_ADDRESS = makeAddr("l2RewardsManagerMock");

    function run() public {
        vm.startBroadcast();

        _loadExistingContractsAddresses();

        // XPufETHBurner
        XPufETHBurner xPufETHBurnerImpl = new XPufETHBurner({
            XpufETH: xPufETH,
            pufETH: pufferVault,
            lockbox: lockbox,
            l2RewardsManager: L2_REWARDS_MANAGER_ADDRESS
        });

        XPufETHBurner xPufETHBurnerProxy = XPufETHBurner(
            address(
                new ERC1967Proxy(
                    address(xPufETHBurnerImpl), abi.encodeCall(XPufETHBurner.initialize, (address(accessManager)))
                )
            )
        );

        vm.label(address(xPufETHBurnerImpl), "xPufETHBurnerImpl");
        vm.label(address(xPufETHBurnerProxy), "XPufETHBurnerProxy");
    }
}
