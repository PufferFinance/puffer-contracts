// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { L1RewardManager } from "src/L1RewardManager.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { XERC20Lockbox } from "../src/XERC20Lockbox.sol";
import { GenerateRewardManagerCalldata } from "./AccessManagerMigrations/03_GenerateRewardManagerCalldata.s.sol";
/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/UpgradeL2RewardManager.s.sol:UpgradeL2RewardManager -vvvv --rpc-url=...
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */

contract UpgradeL2RewardManager is DeployerHelper {
    address l1RewardManagerProxy = address(0x157788cc028Ac6405bD406f2D1e0A8A22b3cf17b);
    address l2RewardsManagerProxy = _getL2RewardsManager();

    bytes public upgradeCallData;
    bytes public accessManagerCallData;

    function run() public {
        GenerateRewardManagerCalldata calldataGenerator = new GenerateRewardManagerCalldata();

        vm.startBroadcast();

        _getDeployer();

        L2RewardManager newImplementation =
            new L2RewardManager(address(l1RewardManagerProxy), address(_getDeprecatedXPufETH())); // L1 proxy address
        vm.label(address(newImplementation), "L2RewardManagerImplementation");
        console.log("L2RewardManager Implementation", address(newImplementation));

        upgradeCallData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newImplementation), ""));
        console.log("Queue TX From Timelock to -> l2RewardsManagerProxy", l2RewardsManagerProxy);
        console.logBytes(upgradeCallData);
        console.log("================================================");
        accessManagerCallData = calldataGenerator.generateL2Calldata(address(l2RewardsManagerProxy), _getLayerZeroV2Endpoint());

        console.log("Queue from Timelock -> AccessManager", _getAccessManager());
        console.logBytes(accessManagerCallData);

        vm.stopBroadcast();
    }
}
