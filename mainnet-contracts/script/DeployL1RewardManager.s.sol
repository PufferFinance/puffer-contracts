// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { L1RewardManager } from "src/L1RewardManager.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_L1_REWARD_MANAGER, ROLE_ID_BRIDGE } from "./Roles.sol";
import { PufferVaultV3 } from "src/PufferVaultV3.sol";

/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/DeployL1RewardManager.s.sol:DeployL1RewardManager -vvvv --rpc-url=...
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */
contract DeployL1RewardManager is DeployerHelper {
    // https://docs.connext.network/resources/deployments
    address EVERCLEAR_BRIDGE = 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6;

    //@todo Update the address
    address L2_REWARDS_MANAGER_ADDRESS = makeAddr("l2RewardsManagerMock");

    function run() public {
        vm.startBroadcast();

        _loadExistingContractsAddresses();

        // L1RewardManager
        L1RewardManager l1RewardManagerImpl = new L1RewardManager({
            XpufETH: xPufETH,
            pufETH: pufferVault,
            lockbox: lockbox,
            l2RewardsManager: L2_REWARDS_MANAGER_ADDRESS
        });

        L1RewardManager l1ReawrdManagerProxy = L1RewardManager(
            address(
                new ERC1967Proxy(
                    address(l1RewardManagerImpl), abi.encodeCall(L1RewardManager.initialize, (address(accessManager)))
                )
            )
        );

        vm.label(address(l1RewardManagerImpl), "l1RewardManagerImpl");
        vm.label(address(l1ReawrdManagerProxy), "XPufETHBurnerProxy");

        bytes[] memory calldatas = new bytes[](4);

        bytes4[] memory bridgeSelectors = new bytes4[](1);
        bridgeSelectors[0] = L1RewardManager.xReceive.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(l1ReawrdManagerProxy), bridgeSelectors, ROLE_ID_BRIDGE
        );

        calldatas[1] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_BRIDGE, EVERCLEAR_BRIDGE, 0);

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

        bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));

        console.log("Multicall data:");
        console.logBytes(multicallData);
    }
}
