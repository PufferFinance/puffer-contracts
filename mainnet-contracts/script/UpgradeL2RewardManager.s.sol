// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { L1RewardManager } from "src/L1RewardManager.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { XERC20Lockbox } from "../src/XERC20Lockbox.sol";
/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/UpgradeL2RewardManager.s.sol:UpgradeL2RewardManager -vvvv --rpc-url=...
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */

contract UpgradeL2RewardManager is DeployerHelper {
    address l1RewardManagerProxy = address(0x016810D99Bdec8F8D26646b6B74D751f7b1a55a2);
    address l2RewardsManagerProxy = address(0xF7cd14c371bF9bE0BD2F210d72aF597da493F96C);
    address l1PufferVault;

    function run() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"));

        vm.startBroadcast();
        // Load addresses for Sepolia
        _getDeployer();

        //deploy new LockBox contract if needed
        // XERC20Lockbox lockbox = new XERC20Lockbox({
        //     xerc20: xPufETH,
        //     erc20: pufferVault
        // });

        // L1RewardManager
        L1RewardManager l1RewardManagerImpl = new L1RewardManager({
            xPufETH: _getXPufETH(),
            pufETH: _getPufferVault(),
            lockbox: _getLockbox(),
            l2RewardsManager: l2RewardsManagerProxy
        });
        vm.label(address(l1RewardManagerImpl), "l1RewardManagerImpl");

        // For testnet, the deployer can execute the upgrade
        UUPSUpgradeable(l1RewardManagerProxy).upgradeToAndCall(address(l1RewardManagerImpl), "");
        vm.stopBroadcast();

        // Upgrade stuff on L2
        vm.createSelectFork(vm.rpcUrl("opsepolia"));
        vm.startBroadcast();
        // Load addresses for Sepolia
        _getDeployer();

        L2RewardManager newImplementation = new L2RewardManager(_getXPufETH(), address(l1RewardManagerProxy));
        console.log("L2RewardManager Implementation", address(newImplementation));

        UUPSUpgradeable(l2RewardsManagerProxy).upgradeToAndCall(address(newImplementation), "");
        vm.stopBroadcast();
    }
}
