// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { DeployerHelper } from "./DeployerHelper.s.sol";
import { console } from "forge-std/console.sol";
import { PermissionedModule } from "../src/PermissionedModule.sol";
import { NonRestakingWithdrawalCredentials } from "../src/NonRestakingWithdrawalCredentials.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { IDelegationManager } from "../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IRewardsCoordinator } from "../src/interface/Eigenlayer-Slashing/IRewardsCoordinator.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title DeployPermissionedBeacons
 * @author Puffer Finance
 * @notice Deploys the PermissionedModule and NonRestakingWithdrawalCredentials beacons.
 * @dev These are new beacons required by PufferModuleManager to create PermissionedModule
 *      instances (each with an associated NonRestakingWithdrawalCredentials sub-contract).
 *
 *      After deploying the beacons, upgrade PufferModuleManager via DeployPufferModuleManager
 *      passing the returned beacon addresses.
 *
 *      forge script script/DeployPermissionedBeacons.s.sol:DeployPermissionedBeacons \
 *          -vvvv --rpc-url=$RPC_URL --broadcast --verify
 */
contract DeployPermissionedBeacons is DeployerHelper {
    function run() public returns (address permissionedModuleBeacon, address nrwcBeacon) {
        vm.startBroadcast();

        (permissionedModuleBeacon, nrwcBeacon) = _deploy();

        vm.stopBroadcast();
    }

    function _deploy() internal returns (address permissionedModuleBeacon, address nrwcBeacon) {
        address accessManager = _getAccessManager();

        // Deploy PermissionedModule implementation
        PermissionedModule permissionedModuleImpl = new PermissionedModule(
            PufferProtocol(payable(_getPufferProtocol())),
            _getEigenPodManager(),
            IDelegationManager(_getDelegationManager()),
            PufferModuleManager(payable(_getPufferModuleManager())),
            IRewardsCoordinator(_getRewardsCoordinator())
        );
        vm.label(address(permissionedModuleImpl), "PermissionedModuleImplementation");
        console.log("Deployed PermissionedModuleImplementation at", address(permissionedModuleImpl));

        // Deploy NonRestakingWithdrawalCredentials implementation
        NonRestakingWithdrawalCredentials nrwcImpl = new NonRestakingWithdrawalCredentials();
        vm.label(address(nrwcImpl), "NonRestakingWithdrawalCredentialsImplementation");
        console.log("Deployed NonRestakingWithdrawalCredentialsImplementation at", address(nrwcImpl));

        // Deploy beacons — owned by AccessManager so upgrades go through DAO/timelock
        UpgradeableBeacon pmBeacon = new UpgradeableBeacon(address(permissionedModuleImpl), accessManager);
        vm.label(address(pmBeacon), "PermissionedModuleBeacon");
        console.log("Deployed PermissionedModuleBeacon at", address(pmBeacon));

        UpgradeableBeacon nrwcBeaconContract = new UpgradeableBeacon(address(nrwcImpl), accessManager);
        vm.label(address(nrwcBeaconContract), "NonRestakingWithdrawalCredentialsBeacon");
        console.log("Deployed NonRestakingWithdrawalCredentialsBeacon at", address(nrwcBeaconContract));

        console.log("================================================");
        console.log("Next step: upgrade PufferModuleManager with these beacon addresses:");
        console.log("  forge script script/DeployPufferModuleManager.s.sol:DeployPufferModuleManager \\");
        console.log("      --sig 'run(address,address)' \\");
        console.log("      ", address(pmBeacon), address(nrwcBeaconContract));
        console.log("================================================");

        return (address(pmBeacon), address(nrwcBeaconContract));
    }
}
