// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ROLE_ID_BRIDGE, ROLE_ID_L1_REWARD_MANAGER } from "../script/Roles.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { IL2RewardManager } from "l2-contracts/src/interface/IL2RewardManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { NoImplementation } from "../src/NoImplementation.sol";
import { L1RewardManager } from "src/L1RewardManager.sol";
import { PufferVaultV3 } from "src/PufferVaultV3.sol";
import { PufferVaultV3Mock } from "src/PufferVaultV3Mock.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { XERC20Lockbox } from "src/XERC20Lockbox.sol";

/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/DeployL2RewardManagerBSC_Base.s.sol:DeployL2RewardManagerBSC_Base -vvvv --rpc-url=...
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */
contract DeployL2RewardManagerBSC_Base is DeployerHelper {
    address l1ReawrdManagerProxy;
    address l2RewardsManagerProxy;
    // address lockbox;
    // address pufferVault;

    function run() public {
        // vm.createSelectFork(vm.rpcUrl("https://rpc.tenderly.co/fork/823669ec-8e80-43ab-ba9d-0fe04599cee7"));
        vm.createSelectFork(vm.rpcUrl("https://virtual.binance.rpc.tenderly.co/f85701de-2d52-4149-beee-d119b137213a"));

        vm.startBroadcast();
        // Load addresses for Binance
        _loadExistingContractsAddresses();

        // TODO
        // missing xpufth + roles
        // roles for lockbox

        // 0. deploy access manager
        accessManager = new AccessManager(deployer);

        // 1. deploy l1 vault mock
        PufferVaultV3Mock pufferVaultV3 = new PufferVaultV3Mock();
        pufferVault = address(pufferVaultV3);

        // 2. deploy new LockBox contract
        XERC20Lockbox xerc20Lockbox = new XERC20Lockbox({ xerc20: xPufETH, erc20: pufferVault });
        lockbox = address(xerc20Lockbox);

        address noImpl = address(new NoImplementation());

        // Deploy empty proxy
        l1ReawrdManagerProxy = address(new ERC1967Proxy(noImpl, ""));

        vm.label(address(l1ReawrdManagerProxy), "L1RewardManagerProxy");

        bytes[] memory calldatas = new bytes[](4);

        bytes4[] memory bridgeSelectors = new bytes4[](1);
        bridgeSelectors[0] = L1RewardManager.xReceive.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(l1ReawrdManagerProxy), bridgeSelectors, ROLE_ID_BRIDGE
        );

        calldatas[1] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_BRIDGE, everclearBridge, 0);

        bytes4[] memory vaultSelectors = new bytes4[](1);
        vaultSelectors[0] = PufferVaultV3.revertMintRewards.selector;

        calldatas[2] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(pufferVault),
            vaultSelectors,
            ROLE_ID_L1_REWARD_MANAGER
        );

        calldatas[3] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_L1_REWARD_MANAGER, l1ReawrdManagerProxy, 0);

        // For non-mainnet, the deployer can execute the upgrade
        if (block.chainid != mainnet) {
            accessManager.multicall(calldatas);
        }
        bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));

        console.log("Multicall L1 data:");
        console.logBytes(multicallData);

        vm.stopBroadcast();

        // Deploy stuff on L2 - Base
        // vm.createSelectFork(vm.rpcUrl("https://rpc.tenderly.co/fork/20fa915a-d22b-4100-8f7c-15a9c553445f"));
        vm.createSelectFork(vm.rpcUrl("https://virtual.base.rpc.tenderly.co/e6034964-d79e-4210-937b-7312fbc7dd8f"));
        vm.startBroadcast();
        // Load addresses for Base
        _loadExistingContractsAddresses();

        accessManager = new AccessManager(deployer);

        L2RewardManager newImplementation =
            new L2RewardManager({ xPufETH: xPufETH, l1RewardManager: address(l1ReawrdManagerProxy) });
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
        bridgeSelectorsL2[0] = L2RewardManager.xReceive.selector;

        calldatasL2[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(l2RewardsManagerProxy),
            bridgeSelectorsL2,
            ROLE_ID_BRIDGE
        );
        calldatasL2[1] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_BRIDGE, everclearBridge, 0);

        // For non-mainnet, the deployer can execute the upgrade
        if (block.chainid != mainnet) {
            accessManager.multicall(calldatasL2);
        }

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatasL2));

        console.log("Encoded Multicall");
        console.logBytes(encodedMulticall);

        // Upgrade contract on L1
        vm.stopBroadcast();

        // Switch back to Fork 0
        vm.selectFork(0);
        vm.startBroadcast();
        // Load addresses for BSC
        _loadExistingContractsAddresses();

        vm.makePersistent(l2RewardsManagerProxy);

        // L1RewardManager
        L1RewardManager l1RewardManagerImpl = new L1RewardManager({
            XpufETH: xPufETH,
            pufETH: pufferVault,
            lockbox: lockbox,
            l2RewardsManager: l2RewardsManagerProxy
        });

        vm.label(address(l1RewardManagerImpl), "l1RewardManagerImpl");

        bytes memory upgradeCd = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            address(l1RewardManagerImpl),
            abi.encodeCall(L1RewardManager.initialize, (address(accessManager)))
        );

        // // For testnet, the deployer can execute the upgrade
        UUPSUpgradeable(l1ReawrdManagerProxy).upgradeToAndCall(
            address(l1RewardManagerImpl), abi.encodeCall(L1RewardManager.initialize, (address(accessManager)))
        );

        // // For non-mainnet, the deployer can execute the upgrade
        // if (block.chainid != mainnet) {
        //     accessManager.execute(address(l1ReawrdManagerProxy), upgradeCd);
        // }

        console.log("Upgrade CD target", address(l1RewardManagerImpl));
        console.logBytes(upgradeCd);

        vm.stopBroadcast();
    }
}
