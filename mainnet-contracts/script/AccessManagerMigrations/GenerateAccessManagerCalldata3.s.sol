// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { console } from "forge-std/console.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { PufferVaultV3 } from "../../src/PufferVaultV3.sol";
import { L1RewardManager } from "../../src/L1RewardManager.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import {
    ROLE_ID_DAO,
    ROLE_ID_BRIDGE,
    ROLE_ID_OPERATIONS_PAYMASTER,
    ROLE_ID_L1_REWARD_MANAGER,
    ROLE_ID_VAULT_WITHDRAWER,
    PUBLIC_ROLE
} from "../../script/Roles.sol";

/**
 * @title GenerateAccessManagerCalldata3
 * @author Puffer Finance
 * @notice Generates the AccessManager call data to setup the public access
 * The returned calldata is queued and executed by the Operations Multisig
 * 1. timelock.queueTransaction(address(accessManager), encodedMulticall, 1)
 * 2. ... 7 days later ...
 * 3. timelock.executeTransaction(address(accessManager), encodedMulticall, 1)
 */
contract GenerateAccessManagerCalldata3 is Script {
    function generateL1Calldata(
        address l1RewardManagerProxy,
        address l1Bridge,
        address pufferVaultProxy,
        address pufferModuleManagerProxy
    ) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](9);

        bytes4[] memory paymasterSelectors = new bytes4[](1);
        paymasterSelectors[0] = L1RewardManager.mintAndBridgeRewards.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            l1RewardManagerProxy,
            paymasterSelectors,
            ROLE_ID_OPERATIONS_PAYMASTER
        );

        bytes4[] memory bridgeSelectors = new bytes4[](1);
        bridgeSelectors[0] = L1RewardManager.xReceive.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, l1RewardManagerProxy, bridgeSelectors, ROLE_ID_BRIDGE
        );

        calldatas[2] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_BRIDGE, l1Bridge, 0);

        bytes4[] memory daoSelectors = new bytes4[](3);
        daoSelectors[0] = L1RewardManager.updateBridgeData.selector;
        daoSelectors[1] = L1RewardManager.setAllowedRewardMintAmount.selector;
        daoSelectors[2] = L1RewardManager.setAllowedRewardMintFrequency.selector;

        calldatas[3] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, l1RewardManagerProxy, daoSelectors, ROLE_ID_DAO
        );

        bytes4[] memory vaultSelectors = new bytes4[](2);
        vaultSelectors[0] = PufferVaultV3.mintRewards.selector;
        vaultSelectors[1] = PufferVaultV3.revertMintRewards.selector;
        calldatas[4] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, pufferVaultProxy, vaultSelectors, ROLE_ID_L1_REWARD_MANAGER
        );

        calldatas[5] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_L1_REWARD_MANAGER, l1RewardManagerProxy, 0);

        bytes4[] memory pufferModuleManagerSelectors = new bytes4[](1);
        pufferModuleManagerSelectors[0] = PufferVaultV3.depositRewards.selector;

        calldatas[6] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            pufferVaultProxy,
            pufferModuleManagerSelectors,
            ROLE_ID_VAULT_WITHDRAWER
        );

        calldatas[7] = abi.encodeWithSelector(
            AccessManager.grantRole.selector, ROLE_ID_VAULT_WITHDRAWER, pufferModuleManagerProxy, 0
        );

        bytes4[] memory paymasterSelectorsOnModuleManager = new bytes4[](1);
        paymasterSelectorsOnModuleManager[0] = PufferModuleManager.transferRewardsToTheVault.selector;

        calldatas[8] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            pufferModuleManagerProxy,
            paymasterSelectorsOnModuleManager,
            ROLE_ID_OPERATIONS_PAYMASTER
        );

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        // console.log("GenerateAccessManagerCallData:");
        // console.logBytes(encodedMulticall);

        return encodedMulticall;
    }

    function generateL2Calldata(address l2RewardManagerProxy, address l2Bridge) public pure returns (bytes memory) {
        bytes[] memory calldatasL2 = new bytes[](5);

        bytes4[] memory bridgeSelectorsL2 = new bytes4[](1);
        bridgeSelectorsL2[0] = L2RewardManager.xReceive.selector;

        calldatasL2[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(l2RewardManagerProxy),
            bridgeSelectorsL2,
            ROLE_ID_BRIDGE
        );

        calldatasL2[1] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_BRIDGE, l2Bridge, 0);

        bytes4[] memory publicSelectors = new bytes4[](1);
        publicSelectors[0] = L2RewardManager.claimRewards.selector;

        calldatasL2[2] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(l2RewardManagerProxy), publicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory paymasterSelectors = new bytes4[](3);
        paymasterSelectors[0] = L2RewardManager.freezeAndRevertInterval.selector;
        paymasterSelectors[1] = L2RewardManager.freezeClaimingForInterval.selector;
        paymasterSelectors[2] = L2RewardManager.revertInterval.selector;

        calldatasL2[3] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(l2RewardManagerProxy), paymasterSelectors, ROLE_ID_DAO
        );

        bytes4[] memory daoSelectors = new bytes4[](2);
        daoSelectors[0] = L2RewardManager.updateBridgeData.selector;
        daoSelectors[1] = L2RewardManager.setDelayPeriod.selector;

        calldatasL2[4] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(l2RewardManagerProxy), daoSelectors, ROLE_ID_DAO
        );

        // DAO role is assigned to OPS Multisig on Base

        return abi.encodeCall(Multicall.multicall, (calldatasL2));
    }
}
