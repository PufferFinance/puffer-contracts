// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { NoImplementation } from "../src/NoImplementation.sol";
import { L1RewardManager } from "src/L1RewardManager.sol";
import { GenerateAccessManagerCalldata3 } from "script/AccessManagerMigrations/GenerateAccessManagerCalldata3.s.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/DeployFWR.s.sol:DeployFWR -vvvv --account
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */
contract DeployFWR is DeployerHelper {
    address l1RewardManagerProxy;
    address l2RewardManagerProxy;

    uint256 mainnetForkNumber;

    function run() public {
        GenerateAccessManagerCalldata3 generator = new GenerateAccessManagerCalldata3();

        mainnetForkNumber = vm.createSelectFork(vm.rpcUrl("mainnet"));

        vm.startBroadcast();

        address noImpl = address(new NoImplementation());

        // Deploy empty proxy
        l1RewardManagerProxy = address(new ERC1967Proxy(noImpl, ""));

        vm.label(address(l1RewardManagerProxy), "l1RewardManagerProxy");

        // Generate L1 calldata
        bytes memory l1AccessManagerCalldata = generator.generateL1Calldata({
            l1RewardManagerProxy: l1RewardManagerProxy,
            l1Bridge: _getEverclear(),
            pufferVaultProxy: _getPufferVault(),
            pufferModuleManagerProxy: _getPufferModuleManager()
        });

        console.log("L1 Access Manager Calldata");
        console.logBytes(l1AccessManagerCalldata);

        vm.stopBroadcast();

        // Deploy contracts on L2
        vm.createSelectFork(vm.rpcUrl("base"));
        vm.startBroadcast();

        L2RewardManager newImplementation = new L2RewardManager(_getXPufETH(), address(l1RewardManagerProxy));

        console.log("L2RewardManager Implementation", address(newImplementation));

        l2RewardManagerProxy = address(
            new ERC1967Proxy(
                address(newImplementation), abi.encodeCall(L2RewardManager.initialize, (_getAccessManager()))
            )
        );
        vm.makePersistent(l2RewardManagerProxy);

        console.log("L2RewardManager Proxy", address(l2RewardManagerProxy));
        vm.label(address(l2RewardManagerProxy), "L2RewardManagerProxy");
        vm.label(address(newImplementation), "L2RewardManagerImplementation");

        bytes memory l2AccessManagerCalldata =
            generator.generateL2Calldata({ l2RewardManagerProxy: l2RewardManagerProxy, l2Bridge: _getEverclear() });

        console.log("L2 Access Manager Calldata");
        console.logBytes(l2AccessManagerCalldata);

        // Upgrade contract on L1
        vm.stopBroadcast();

        // Switch back to mainnet
        vm.selectFork(mainnetForkNumber);
        vm.startBroadcast();

        // L1RewardManager
        L1RewardManager l1ReeardManagerImpl = new L1RewardManager({
            xPufETH: _getXPufETH(),
            pufETH: _getPufferVault(),
            lockbox: _getLockbox(),
            l2RewardsManager: l2RewardManagerProxy
        });

        vm.label(address(l1ReeardManagerImpl), "l1ReeardManagerImpl");

        // The deployer can execute the upgrade right away because of NoImplementation contract
        UUPSUpgradeable(l1RewardManagerProxy).upgradeToAndCall(
            address(l1ReeardManagerImpl), abi.encodeCall(L1RewardManager.initialize, (_getAccessManager()))
        );

        vm.stopBroadcast();
    }
}
