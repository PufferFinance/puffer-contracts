// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { RestakingOperator } from "../src/RestakingOperator.sol";
import { IDelegationManager } from "../src/interface/EigenLayer-Slashing/IDelegationManager.sol";
import { IAllocationManager } from "../src/interface/EigenLayer-Slashing/IAllocationManager.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IRewardsCoordinator } from "../src/interface/EigenLayer-Slashing/IRewardsCoordinator.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";

/**
 * forge script script/DeployRestakingOperator.s.sol:DeployRestakingOperator --rpc-url=$RPC_URL --private-key $PK
 *
 * deploy along with verification:
 * forge script script/DeployRestakingOperator.s.sol:DeployRestakingOperator -vvvv --rpc-url=$HOLESKY_RPC_URL --account puffer --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast
 */
contract DeployRestakingOperator is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        RestakingOperator restakingOperatorImplementation = new RestakingOperator({
            delegationManager: IDelegationManager(_getEigenDelegationManager()),
            allocationManager: IAllocationManager(_getEigenSlasher()),
            moduleManager: PufferModuleManager(payable(_getPufferModuleManager())),
            rewardsCoordinator: IRewardsCoordinator(_getRewardsCoordinator())
        });

        vm.label(address(restakingOperatorImplementation), "RestakingOperatorImplementation");

        bytes memory cd = abi.encodeCall(UpgradeableBeacon.upgradeTo, address(restakingOperatorImplementation));

        bytes memory calldataToExecute = abi.encodeCall(AccessManager.execute, (_getRestakingOperatorBeacon(), cd));

        console.log("From Timelock queue a tx to accessManager");
        console.logBytes(calldataToExecute);

        if (block.chainid == holesky) {
            AccessManager(_getAccessManager()).execute(_getRestakingOperatorBeacon(), cd);
        }
    }
}
