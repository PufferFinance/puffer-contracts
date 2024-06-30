// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { IPufferModuleManager } from "../src/interface/IPufferModuleManager.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { RestakingOperator } from "../src/RestakingOperator.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISlasher } from "eigenlayer/interfaces/ISlasher.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IRewardsCoordinator } from "../src/interface/EigenLayer/IRewardsCoordinator.sol";

/**
 * forge script script/DeployRestakingOperator.s.sol:DeployRestakingOperator --rpc-url=$RPC_URL --private-key $PK
 *
 */
contract DeployRestakingOperator is Script {
    address ACCESS_MANAGER = 0xA6c916f85DAfeb6f726E03a1Ce8d08cf835138fF;
    address RESTAKING_OPERATOR_BEACON = 0xa7DC88c059F57ADcE41070cEfEFd31F74649a261;

    function run() public {
        require(block.chainid == 17000, "This script is only for Puffer Holesky testnet");

        vm.startBroadcast();
        RestakingOperator impl = new RestakingOperator({
            delegationManager: IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7),
            slasher: ISlasher(0xcAe751b75833ef09627549868A04E32679386e7C),
            moduleManager: IPufferModuleManager(0xe4695ab93163F91665Ce5b96527408336f070a71),
            rewardsCoordinator: IRewardsCoordinator(0xAcc1fb458a1317E886dB376Fc8141540537E68fE)
        });

        bytes memory cd = abi.encodeCall(UpgradeableBeacon.upgradeTo, address(impl));

        // AccessManager is the owner of upgradeable beacon for restaking operator
        AccessManager(ACCESS_MANAGER).execute(RESTAKING_OPERATOR_BEACON, cd);
    }
}
