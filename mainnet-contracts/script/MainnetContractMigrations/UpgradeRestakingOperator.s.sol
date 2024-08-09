// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { RestakingOperator } from "../../src/RestakingOperator.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISlasher } from "eigenlayer/interfaces/ISlasher.sol";
import { GenerateAccessManagerCalldata1 } from "script/AccessManagerMigrations/GenerateAccessManagerCalldata1.s.sol";
import { IRewardsCoordinator } from "../../src/interface/EigenLayer/IRewardsCoordinator.sol";

/**
 *     Use either -account or --private-key to sign the transaction
 *
 * To run the simulation run:
 *    forge script script/MainnetContractMigrations/UpgradePufferModule.s.sol:UpgradePufferModule -vvvv --rpc-url=$RPC_URL
 *
 * To run the deployment add --broadcast --verify
 */
contract UpgradeRestakingOperator is Script {
    address DELEGATION_MANAGER = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
    address EIGEN_SLASHER = 0xD92145c07f8Ed1D392c1B88017934E301CC1c3Cd;
    address MODULE_MANAGER_PROXY = 0x9E1E4fCb49931df5743e659ad910d331735C3860;
    address MODULE_BEACON = 0xdd38A5a7789C74fc7F64556fc772343658EEBb04;
    address REWARDS_COORDINATOR = 0x7750d328b314EfFa365A0402CcfD489B80B0adda;
    address RESTAKING_OPERATOR_BEACON = 0x6756B856Dd3843C84249a6A31850cB56dB824c4B;
    address PUFFER_PROTOCOL = 0xf7b6B32492c2e13799D921E84202450131bd238B;
    address DAO = 0xC0896ab1A8cae8c2C1d27d011eb955Cca955580d;
    address ACCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;

    function run() public {
        require(block.chainid == 1, "This script is only for Puffer Mainnet");
        vm.startBroadcast();

        RestakingOperator restakingOperatorImpl = new RestakingOperator({
            delegationManager: IDelegationManager(DELEGATION_MANAGER),
            slasher: ISlasher(EIGEN_SLASHER),
            moduleManager: PufferModuleManager(MODULE_MANAGER_PROXY),
            rewardsCoordinator: IRewardsCoordinator(REWARDS_COORDINATOR)
        });

        // bytes memory accessCd =
        //     new GenerateAccessManagerCalldata1().run(MODULE_MANAGER_PROXY, address(avsRegistry), DAO);

        bytes memory cd1 = abi.encodeCall(UpgradeableBeacon.upgradeTo, address(restakingOperatorImpl));
        bytes memory cd2 = abi.encodeCall(AccessManager.execute, (RESTAKING_OPERATOR_BEACON, cd1));

        // calldata to execute using the timelock contract. setting the target as the Access Manager
        console.log("From Timelock queue a tx to accessManager");
        console.logBytes(cd2);
    }
}
