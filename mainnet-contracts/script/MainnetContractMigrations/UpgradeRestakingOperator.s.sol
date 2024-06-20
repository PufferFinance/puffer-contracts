// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { AVSContractsRegistry } from "../../src/AVSContractsRegistry.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { RestakingOperator } from "../../src/RestakingOperator.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISlasher } from "eigenlayer/interfaces/ISlasher.sol";
import { GenerateAccessManagerCalldata1 } from "script/AccessManagerMigrations/GenerateAccessManagerCalldata1.s.sol";
import { IRewardsCoordinator } from "../../src/interface/EigenLayer/IRewardsCoordinator.sol";

/**
 * forge script script/MainnetContractMigrations/UpgradeRestakingOperator.s.sol:UpgradeRestakingOperator --rpc-url=$RPC_URL --private-key $PK
 */
contract UpgradeRestakingOperator is Script {
    address DELEGATION_MANAGER = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
    address EIGEN_SLASHER = 0xD92145c07f8Ed1D392c1B88017934E301CC1c3Cd;
    address MODULE_MANAGER_PROXY = 0x9E1E4fCb49931df5743e659ad910d331735C3860;
    address MODULE_BEACON = 0xdd38A5a7789C74fc7F64556fc772343658EEBb04;
    address RESTAKING_OPERATOR_BEACON = 0x6756B856Dd3843C84249a6A31850cB56dB824c4B;
    address PUFFER_PROTOCOL = 0xf7b6B32492c2e13799D921E84202450131bd238B;
    address DAO = 0xC0896ab1A8cae8c2C1d27d011eb955Cca955580d;
    address ACCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;

    function run() public {
        require(block.chainid == 1, "This script is only for Puffer Mainnet");
        vm.startBroadcast();

        AVSContractsRegistry avsRegistry = new AVSContractsRegistry(address(ACCESS_MANAGER));

        PufferModuleManager pufferModuleManagerImpl = new PufferModuleManager({
            pufferModuleBeacon: MODULE_BEACON,
            restakingOperatorBeacon: RESTAKING_OPERATOR_BEACON,
            pufferProtocol: PUFFER_PROTOCOL,
            avsContractsRegistry: avsRegistry
        });

        RestakingOperator restakingOperatorImpl = new RestakingOperator({
            delegationManager: IDelegationManager(DELEGATION_MANAGER),
            slasher: ISlasher(EIGEN_SLASHER),
            moduleManager: PufferModuleManager(MODULE_MANAGER_PROXY),
            rewardsCoordinator: IRewardsCoordinator(address(0))
        });

        bytes memory accessCd =
            new GenerateAccessManagerCalldata1().run(MODULE_MANAGER_PROXY, address(avsRegistry), DAO);

        bytes memory cd1 = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(pufferModuleManagerImpl), ""));
        bytes memory cd2 = abi.encodeCall(UpgradeableBeacon.upgradeTo, address(restakingOperatorImpl));
        bytes memory cd3 = abi.encodeCall(AccessManager.execute, (MODULE_MANAGER_PROXY, cd1));
        bytes memory cd4 = abi.encodeCall(AccessManager.execute, (RESTAKING_OPERATOR_BEACON, cd2));

        // calldata to execute using the timelock contract. setting the target as the Access Manager
        console.logBytes(cd3);
        console.logBytes(cd4);
        console.logBytes(accessCd);

        // AccessManager is the owner of upgradeable beacon for restaking operator & module manager
        // AccessManager(ACCESS_MANAGER).execute(MODULE_MANAGER_PROXY, cd1);
        // AccessManager(ACCESS_MANAGER).execute(RESTAKING_OPERATOR_BEACON, cd2);
    }
}
