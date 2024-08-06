// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ROLE_ID_BRIDGE, ROLE_ID_REWARD_BURNER } from "../script/Roles.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { IL2RewardManager } from "l2-contracts/src/interface/IL2RewardManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { NoImplementation } from "../src/NoImplementation.sol";
import { XPufETHBurner } from "src/XPufETHBurner.sol";
import { PufferVaultV3 } from "src/PufferVaultV3.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/DeployL2RewardManager.s.sol:DeployL2RewardManager -vvvv --rpc-url=...
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */
contract DeployL2RewardManager is DeployerHelper {
    address xPufETHBurnerProxy;
    address l2RewardsManagerProxy;
    address l1PufferVault;

    function run() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"));

        vm.startBroadcast();
        // Load addresses for Sepolia
        _loadExistingContractsAddresses();
        l1PufferVault = pufferVault;

        address noImpl = address(new NoImplementation());

        // Deploy empty proxy
        xPufETHBurnerProxy = address(new ERC1967Proxy(noImpl, ""));

        vm.label(address(xPufETHBurnerProxy), "XPufETHBurnerProxy");

        bytes[] memory calldatas = new bytes[](4);

        bytes4[] memory bridgeSelectors = new bytes4[](1);
        bridgeSelectors[0] = XPufETHBurner.xReceive.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(xPufETHBurnerProxy), bridgeSelectors, ROLE_ID_BRIDGE
        );

        calldatas[1] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_BRIDGE, everclearBridge, 0);

        bytes4[] memory vaultSelectors = new bytes4[](1);
        vaultSelectors[0] = PufferVaultV3.revertBridgingInterval.selector;

        calldatas[2] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(pufferVault), vaultSelectors, ROLE_ID_REWARD_BURNER
        );

        calldatas[3] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_REWARD_BURNER, xPufETHBurnerProxy, 0);

        bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));

        console.log("Multicall L1 data:");
        console.logBytes(multicallData);

        vm.stopBroadcast();
        // Deploy stuff on L2
        vm.createSelectFork(vm.rpcUrl("opsepolia"));
        vm.startBroadcast();
        // Load addresses for Sepolia
        _loadExistingContractsAddresses();

        L2RewardManager newImplementation =
            new L2RewardManager(everclearBridge, address(l1PufferVault), address(xPufETHBurnerProxy));
        console.log("L2RewardManager Implementation", address(newImplementation));

        l2RewardsManagerProxy = address(
            new ERC1967Proxy(
                address(newImplementation), abi.encodeCall(L2RewardManager.initialize, (address(accessManager)))
            )
        );
        vm.makePersistent(l2RewardsManagerProxy);

        console.log("L2RewardManager Proxy", address(l2RewardsManagerProxy));
        vm.label(address(l2RewardsManagerProxy), "L2RewardManagerProxy");
        vm.label(address(newImplementation), "L2RewardManagerImplementation");

        bytes[] memory calldatasL2 = new bytes[](2);

        bytes4[] memory bridgeSelectorsL2 = new bytes4[](1);
        bridgeSelectorsL2[0] = IL2RewardManager.xReceive.selector;

        calldatasL2[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(l2RewardsManagerProxy),
            bridgeSelectorsL2,
            ROLE_ID_BRIDGE
        );
        calldatasL2[1] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_BRIDGE, everclearBridge, 0);

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatasL2));

        console.log("Encoded Multicall");
        console.logBytes(encodedMulticall);

        // accessManager.multicall(calldatasL2);

        // Upgrade contract on L1
        vm.stopBroadcast();

        // Switch back to Fork 0
        vm.selectFork(0);
        vm.startBroadcast();
        // Load addresses for Sepolia
        _loadExistingContractsAddresses();

        vm.makePersistent(l2RewardsManagerProxy);

        // XPufETHBurner
        XPufETHBurner xPufETHBurnerImpl = new XPufETHBurner({
            XpufETH: xPufETH,
            pufETH: pufferVault,
            lockbox: lockbox,
            l2RewardsManager: l2RewardsManagerProxy
        });

        vm.label(address(xPufETHBurnerImpl), "xPufETHBurnerImpl");

        bytes memory upgradeCd = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            address(xPufETHBurnerImpl),
            abi.encodeCall(XPufETHBurner.initialize, (address(accessManager)))
        );

        // For testnet, the deployer can execute the upgrade
        UUPSUpgradeable(xPufETHBurnerProxy).upgradeToAndCall(
            address(xPufETHBurnerImpl), abi.encodeCall(XPufETHBurner.initialize, (address(accessManager)))
        );

        // accessManager.execute(address(xPufETHBurnerProxy), upgradeCd);

        console.log("Upgrade CD target", address(xPufETHBurnerImpl));
        console.logBytes(upgradeCd);

        vm.stopBroadcast();
    }
}
