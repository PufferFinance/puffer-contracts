// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { NoImplementation } from "../src/NoImplementation.sol";
import { L1RewardManager } from "src/L1RewardManager.sol";
import { GenerateRewardManagerCalldata } from "script/AccessManagerMigrations/03_GenerateRewardManagerCalldata.s.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/DeployFWR.s.sol:DeployFWR -vvvv --account
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */
contract DeployFWR is DeployerHelper {
    address l1RewardManagerProxy = 0x10f970bcb84B82B82a65eBCbF45F26dD26D69F12;
    address l2RewardManagerProxy = 0xD012f4c34c2b7De319Dca0A1F5A87097f53Ac484;

    uint256 mainnetForkNumber;

    function run() public {
        GenerateRewardManagerCalldata generator = new GenerateRewardManagerCalldata();

        mainnetForkNumber = vm.createSelectFork(vm.rpcUrl("holesky"));

        // vm.startBroadcast();

        // // address noImpl = address(new NoImplementation());

        // // // Deploy empty proxy
        // // l1RewardManagerProxy = address(new ERC1967Proxy(noImpl, ""));

        // vm.label(address(l1RewardManagerProxy), "l1RewardManagerProxy");

        // // Generate L1 calldata
        // bytes memory l1AccessManagerCalldata = generator.generateL1Calldata({
        //     l1RewardManagerProxy: l1RewardManagerProxy,
        //     l1Bridge: _getLayerZeroV2Endpoint(),
        //     pufferVaultProxy: _getPufferVault(),
        //     pufferModuleManagerProxy: _getPufferModuleManager()
        // });

        // console.log("L1 Access Manager Calldata");
        // console.logBytes(l1AccessManagerCalldata);

        // (bool success,) = address(_getAccessManager()).call(l1AccessManagerCalldata);
        // console.log("AccessManager.call success", success);
        // require(success, "AccessManager.call failed");

        // vm.stopBroadcast();

        // Deploy contracts on L2
        // vm.createSelectFork(vm.rpcUrl("sepolia"));
        // vm.startBroadcast();

        // L2RewardManager newImplementation = new L2RewardManager(address(l1RewardManagerProxy)); // Using L1 proxy address

        // console.log("L2RewardManager Implementation", address(newImplementation));

        // l2RewardManagerProxy = address(
        //     new ERC1967Proxy(
        //         address(newImplementation),
        //         abi.encodeCall(L2RewardManager.initialize, (_getAccessManager()))
        //     )
        // );
        // vm.makePersistent(l2RewardManagerProxy);

        // console.log("L2RewardManager Proxy", address(l2RewardManagerProxy));
        // vm.label(address(l2RewardManagerProxy), "L2RewardManagerProxy");
        // vm.label(address(newImplementation), "L2RewardManagerImplementation");

        // bytes memory l2AccessManagerCalldata = generator.generateL2Calldata({
        //     l2RewardManagerProxy: l2RewardManagerProxy,
        //     l2Bridge: _getLayerZeroV2Endpoint()
        // });

        // console.log("L2 Access Manager Calldata");
        // console.logBytes(l2AccessManagerCalldata);

        // (success,) = address(_getAccessManager()).call(l2AccessManagerCalldata);
        // console.log("AccessManager.call success", success);
        // require(success, "AccessManager.call failed");

        // // Upgrade contract on L1
        // vm.stopBroadcast();

        // Switch back to mainnet
        // vm.selectFork(mainnetForkNumber);
        vm.startBroadcast();

        // L1RewardManager
        L1RewardManager l1ReeardManagerImpl = new L1RewardManager(
            _getPufferVault(), // pufETH
            l2RewardManagerProxy, // l2RewardsManager
            _getPufETHOFTAdapter() // pufETH_OFT
        );

        vm.label(address(l1ReeardManagerImpl), "l1ReeardManagerImpl");

        // The deployer can execute the upgrade right away because of NoImplementation contract
        UUPSUpgradeable(l1RewardManagerProxy).upgradeToAndCall(address(l1ReeardManagerImpl), "");

        // If on testnet, upgrade and execute access control changes directly
        //  if (block.chainid == holesky) {
        //     // upgrade to implementation
        //     AccessManager(_getAccessManager()).execute(
        //         address(validatorTicket),
        //         abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(validatorTicketImpl), ""))
        //     );

        //     // execute access control changes

        // }

        vm.stopBroadcast();
    }
}
