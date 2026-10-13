// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { L1RewardManager } from "../../src/L1RewardManager.sol";
import {
    ROLE_ID_DAO,
    ROLE_ID_BRIDGE,
    ROLE_ID_L1_REWARD_MANAGER,
    ROLE_ID_REWARDS_MINTER,
    ROLE_ID_REWARD_WATCHER,
    PUBLIC_ROLE,
    ADMIN_ROLE
} from "../../script/Roles.sol";

/**
 * @title GenerateRewardManagerCalldata
 * @author Puffer Finance
 * @notice Generates the AccessManager call data for the reward managers
 * The returned calldata is queued and executed by the Operations Multisig
 * 1. timelock.queueTransaction(address(accessManager), encodedMulticall, 1)
 * 2. ... 7 days later ...
 * 3. timelock.executeTransaction(address(accessManager), encodedMulticall, 1)
 */
contract GenerateRewardManagerCalldata is Script {
    /**
     * @notice Generates the AccessManager calldata for the L1RewardManager, where the rewards are claimed on L1
     * @dev It also closes the functions of the bridging versions and revokes the bridge role.
     * On a new deployment `bridgeRoleHolders` can be empty.
     * @param l1RewardManagerProxy The L1RewardManager proxy
     * @param rewardWatcher The account that can freeze a wrong interval during the claiming delay.
     * Use address(0) to skip the grant
     * @param bridgeRoleHolders The accounts that hold `ROLE_ID_BRIDGE`. The role is revoked from them
     * @param vaultMinterRoleHolders The accounts other than the L1RewardManager that hold `ROLE_ID_L1_REWARD_MANAGER`.
     * The role is revoked from them. Freeze and revert are handled by the L1RewardManager, so nobody else needs to
     * call `PufferVault.mintRewards` or `PufferVault.revertMintRewards`
     */
    function generateL1Calldata(
        address l1RewardManagerProxy,
        address rewardWatcher,
        address[] memory bridgeRoleHolders,
        address[] memory vaultMinterRoleHolders
    ) public pure returns (bytes memory) {
        uint256 watcherGrants = rewardWatcher == address(0) ? 0 : 1;
        bytes[] memory calldatas =
            new bytes[](5 + watcherGrants + bridgeRoleHolders.length + vaultMinterRoleHolders.length);

        bytes4[] memory minterSelectors = new bytes4[](1);
        minterSelectors[0] = L1RewardManager.mintRewards.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, l1RewardManagerProxy, minterSelectors, ROLE_ID_REWARDS_MINTER
        );

        bytes4[] memory publicSelectors = new bytes4[](1);
        publicSelectors[0] = L1RewardManager.claimRewards.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, l1RewardManagerProxy, publicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory watcherSelectors = new bytes4[](1);
        watcherSelectors[0] = L1RewardManager.freezeInterval.selector;

        calldatas[2] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, l1RewardManagerProxy, watcherSelectors, ROLE_ID_REWARD_WATCHER
        );

        bytes4[] memory daoSelectors = new bytes4[](5);
        daoSelectors[0] = L1RewardManager.revertInterval.selector;
        daoSelectors[1] = L1RewardManager.freezeAndRevertInterval.selector;
        daoSelectors[2] = L1RewardManager.setAllowedRewardMintAmount.selector;
        daoSelectors[3] = L1RewardManager.setAllowedRewardMintFrequency.selector;
        daoSelectors[4] = L1RewardManager.setClaimingDelay.selector;

        calldatas[3] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, l1RewardManagerProxy, daoSelectors, ROLE_ID_DAO
        );

        // The functions of the bridging versions do not exist anymore. Their selectors go back to the admin role,
        // so a later implementation can not accidentally expose a function with the same selector to the bridge role
        calldatas[4] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, l1RewardManagerProxy, _deprecatedL1Selectors(), ADMIN_ROLE
        );

        uint256 index = 5;

        if (rewardWatcher != address(0)) {
            calldatas[index++] =
                abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_REWARD_WATCHER, rewardWatcher, 0);
        }

        for (uint256 i = 0; i < bridgeRoleHolders.length; ++i) {
            calldatas[index++] =
                abi.encodeWithSelector(AccessManager.revokeRole.selector, ROLE_ID_BRIDGE, bridgeRoleHolders[i]);
        }

        for (uint256 i = 0; i < vaultMinterRoleHolders.length; ++i) {
            // The L1RewardManager needs the role to mint and revert the rewards
            require(vaultMinterRoleHolders[i] != l1RewardManagerProxy, "Can not revoke the L1RewardManager");
            calldatas[index++] = abi.encodeWithSelector(
                AccessManager.revokeRole.selector, ROLE_ID_L1_REWARD_MANAGER, vaultMinterRoleHolders[i]
            );
        }

        return abi.encodeCall(Multicall.multicall, (calldatas));
    }

    /**
     * @notice Generates the AccessManager calldata that puts the L2RewardManager on Base in claim-only mode
     * @dev The rewards are no longer bridged to Base. The intervals that were bridged before stay claimable, except
     * leaves with `isL1Contract = true` whose account has no claimer: the claimer could only be set with a message
     * from L1. `lzCompose`, freeze, revert and the setters go to the admin role, and the bridge role is revoked from
     * the LayerZero endpoint. A revert from Base after the L1 upgrade would send pufETH to L1 where nothing handles it.
     * @param l2RewardManagerProxy The L2RewardManager proxy on Base
     * @param l2LayerZeroEndpoint The LayerZero V2 endpoint on Base
     */
    function generateL2ClaimOnlyCalldata(address l2RewardManagerProxy, address l2LayerZeroEndpoint)
        public
        pure
        returns (bytes memory)
    {
        bytes[] memory calldatas = new bytes[](2);

        bytes4[] memory closedSelectors = new bytes4[](11);
        // LayerZero version, the implementation that is deployed on Base. The selectors are written out, so that
        // mainnet-contracts does not need to import the L2RewardManager
        closedSelectors[0] = bytes4(keccak256("lzCompose(address,bytes32,bytes,address,bytes)"));
        closedSelectors[1] = bytes4(keccak256("freezeAndRevertInterval(uint256,uint256)"));
        closedSelectors[2] = bytes4(keccak256("freezeClaimingForInterval(uint256,uint256)"));
        closedSelectors[3] = bytes4(keccak256("revertInterval(uint256,uint256)"));
        closedSelectors[4] = bytes4(keccak256("setDelayPeriod(uint256)"));
        closedSelectors[5] = bytes4(keccak256("setPufETHOFT(address)"));
        closedSelectors[6] = bytes4(keccak256("setDestinationEID(uint32)"));
        // Connext version. These functions do not exist anymore, but the selectors are still mapped to roles on Base
        closedSelectors[7] = bytes4(keccak256("xReceive(bytes32,uint256,address,address,uint32,bytes)"));
        closedSelectors[8] = bytes4(keccak256("freezeAndRevertInterval(address,uint256,uint256)"));
        closedSelectors[9] = bytes4(keccak256("revertInterval(address,uint256,uint256)"));
        closedSelectors[10] = bytes4(keccak256("updateBridgeData(address,(uint32))"));

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, l2RewardManagerProxy, closedSelectors, ADMIN_ROLE
        );

        calldatas[1] = abi.encodeWithSelector(AccessManager.revokeRole.selector, ROLE_ID_BRIDGE, l2LayerZeroEndpoint);

        return abi.encodeCall(Multicall.multicall, (calldatas));
    }

    /**
     * @dev Selectors of the L1RewardManager bridging versions
     */
    function _deprecatedL1Selectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        // LayerZero version
        selectors[0] = bytes4(keccak256("mintAndBridgeRewards((uint256,uint256,uint256,bytes32,string))"));
        selectors[1] = bytes4(keccak256("lzCompose(address,bytes32,bytes,address,bytes)"));
        selectors[2] = bytes4(keccak256("setDestinationEID(uint32)"));
        // Connext version
        selectors[3] = bytes4(keccak256("xReceive(bytes32,uint256,address,address,uint32,bytes)"));
        selectors[4] = bytes4(keccak256("updateBridgeData(address,(uint32))"));
        selectors[5] = bytes4(keccak256("mintAndBridgeRewards((address,uint256,uint256,uint256,bytes32,string))"));
    }
}
