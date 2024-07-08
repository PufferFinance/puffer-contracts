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
import {AVSContractsRegistry} from "../../src/AVSContractsRegistry.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UpgradePufferModuleManager
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
 *         PK=${deployer_pk} forge script script/MainnetContractMigrations/UpgradePufferModuleManager.s.sol:UpgradePufferModuleManager -vvvv --rpc-url=$RPC_URL --account puffer --broadcast
 */
contract UpgradePufferModuleManager is BaseScript {
    address pufferModuleBeacon =
        address(0xdd38A5a7789C74fc7F64556fc772343658EEBb04);
    address restakingOperatorBeacon =
        address(0x6756B856Dd3843C84249a6A31850cB56dB824c4B);
    PufferProtocol pufferProtocol =
        PufferProtocol(0xf7b6B32492c2e13799D921E84202450131bd238B);
    AVSContractsRegistry avsContractsRegistry =
        AVSContractsRegistry(0x1565e55b63675c703fcc3778bd33ea97f7be882f);
    address ACCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;
    address PufferModuleManagerProxy =
        0x9E1E4fCb49931df5743e659ad910d331735C3860;

    function run() public broadcast {
        require(block.chainid == 1, "This script is only for Puffer mainnet");
        PufferModuleManager newImplementation = new PufferModuleManager({
            pufferModuleBeacon: address(pufferModuleBeacon),
            restakingOperatorBeacon: address(restakingOperatorBeacon),
            pufferProtocol: address(pufferProtocol),
            avsContractsRegistry: avsContractsRegistry
        });
        console.log("newImplementation", address(newImplementation));

        bytes memory calldataForAM = abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall,
            (address(newImplementation), "")
        );
        console.logBytes(calldataForAM);

        bytes memory calldataToExecute = abi.encodeCall(
            AccessManager.execute,
            (PufferModuleManagerProxy, calldataForAM)
        );
        console.logBytes(calldataToExecute);
    }
}
