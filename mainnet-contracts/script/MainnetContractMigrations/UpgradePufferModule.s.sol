// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {PufferProtocol} from "../../src/PufferProtocol.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {PufferModuleManager} from "../../src/PufferModuleManager.sol";
import { PufferModule } from "../../src/PufferModule.sol";
import { IDelayedWithdrawalRouter } from "eigenlayer/interfaces/IDelayedWithdrawalRouter.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { IRewardsCoordinator } from "../../src/interface/EigenLayer/IRewardsCoordinator.sol";

/**
 * @title UpgradePufferModule
 * @author Puffer Finance
 * @notice Upgrades PufferModuleManager
 * @dev
 *
 *         NOTE:
 *
 *         If you ran the deployment script, but did not `--broadcast` the transaction, it will still update your local chainId-deployment.json file.
 *         Other scripts will fail because addresses will be updated in deployments file, but the deployment never happened.
 *
 *         BaseScript.sol holds the private key logic, if you don't have `PK` ENV variable, it will use the default one PK from `makeAddr("pufferDeployer")`
 *
 *         PK=${deployer_pk} forge script script/MainnetContractMigrations/UpgradePufferModule.s.sol:UpgradePufferModule -vvvv --rpc-url=$RPC_URL --account puffer
 */
contract UpgradePufferModule is BaseScript {

    PufferProtocol pufferProtocol =
        PufferProtocol(payable(0xf7b6B32492c2e13799D921E84202450131bd238B)); 
    address ACCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;
    address PUFFER_MODULE_BEACON =	0xdd38A5a7789C74fc7F64556fc772343658EEBb04;
    PufferModuleManager pufferModuleManager = PufferModuleManager(0x9E1E4fCb49931df5743e659ad910d331735C3860);

    address  eigenPodManager=  0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338;
    IDelayedWithdrawalRouter eigenWithdrawalRouter =  IDelayedWithdrawalRouter(0x7Fe7E9CC0F274d2435AD5d56D5fa73E47F6A23D8);
    IDelegationManager delegationManager = IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    IRewardsCoordinator rewardsCoordinator=IRewardsCoordinator(address(0)); // no address found on https://github.com/Layr-Labs/eigenlayer-contracts?tab=readme-ov-file#deployments

    function run() public broadcast {
        require(
            block.chainid == 1,
            "This script is only for Puffer Mainnet"
        );
        PufferModule newImplementation = new PufferModule({
            protocol: pufferProtocol,
            eigenPodManager: eigenPodManager,
            eigenWithdrawalRouter: eigenWithdrawalRouter,
            delegationManager: delegationManager,
            moduleManager: pufferModuleManager,
            rewardsCoordinator:rewardsCoordinator
        });
        console.log("newImplementation", address(newImplementation));

        bytes memory calldataForAM = abi.encodeCall(
            UpgradeableBeacon.upgradeTo, address(newImplementation));

        console.logBytes(calldataForAM);
 
        bytes memory calldataToExecute = abi.encodeCall(AccessManager.execute, (PUFFER_MODULE_BEACON, calldataForAM));
        console.logBytes(calldataToExecute);

    }
}
