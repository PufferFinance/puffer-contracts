// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { L1RewardManager } from "../src/L1RewardManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { GenerateRewardManagerCalldata } from "./AccessManagerMigrations/03_GenerateRewardManagerCalldata.s.sol";
/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/UpgradeL1RewardManager.s.sol:UpgradeL1RewardManager -vvvv --rpc-url=...
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */

contract UpgradeL1RewardManager is DeployerHelper {
    address l1RewardManagerProxy = _getL1RewardManager();
    address l2RewardsManagerProxy = address(0xF9Dd335bF363b2E4ecFe3c94A86EBD7Dd3Dcf0e7);

    bytes public upgradeCallData;
    bytes public accessManagerCallData;

    function run() public {
        GenerateRewardManagerCalldata calldataGenerator = new GenerateRewardManagerCalldata();

        vm.startBroadcast();
        // Load addresses for Mainnet
        _getDeployer();

        // L1RewardManager
        L1RewardManager l1RewardManagerImpl = new L1RewardManager(
            _getPufferVault(), // pufETH
            l2RewardsManagerProxy, // l2RewardsManager
            _getPufETHOFTAdapter() // pufETH_OFT
        );
        vm.label(address(l1RewardManagerImpl), "l1RewardManagerImpl");

        // For mainnet, we need to prepare calldata so that we can call timelock to upgrade
        // Upgrade on mainnet
        upgradeCallData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(l1RewardManagerImpl), ""));
        console.log("Queue TX From Timelock to -> l1RewardManagerProxy", l1RewardManagerProxy);
        console.logBytes(upgradeCallData);
        console.log("================================================");
        accessManagerCallData = calldataGenerator.generateL1Calldata(address(l1RewardManagerProxy), _getLayerZeroV2Endpoint());

        console.log("Queue from Timelock -> AccessManager", _getAccessManager());
        console.logBytes(accessManagerCallData);

        vm.stopBroadcast();
    }
}
