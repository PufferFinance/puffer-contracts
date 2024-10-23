// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_DAO, ROLE_ID_OPERATIONS_MULTISIG, ROLE_ID_RESTAKING_REWARDS_DEPOSITOR } from "../../script/Roles.sol";
import { PufferRestakingRewardsDepositor } from "../../src/PufferRestakingRewardsDepositor.sol";

contract GenerateRestakingRewardsDepositorCalldata is Script {
    function run(address restakingRewardsDepositorProxy, address operationsMultisig)
        public
        pure
        returns (bytes memory)
    {
        bytes[] memory calldatas = new bytes[](5);

        bytes4[] memory daoSelectors = new bytes4[](3);
        daoSelectors[0] = PufferRestakingRewardsDepositor.setRnoRewardsBps.selector;
        daoSelectors[1] = PufferRestakingRewardsDepositor.setTreasuryRewardsBps.selector;
        daoSelectors[2] = PufferRestakingRewardsDepositor.setRewardsDistributionWindow.selector;

        calldatas[0] = abi.encodeCall(
            AccessManager.setTargetFunctionRole, (restakingRewardsDepositorProxy, daoSelectors, ROLE_ID_DAO)
        );

        bytes4[] memory restakingRewardsDepositorSelectors = new bytes4[](1);
        restakingRewardsDepositorSelectors[0] = PufferRestakingRewardsDepositor.depositRestakingRewards.selector;

        calldatas[1] = abi.encodeCall(
            AccessManager.setTargetFunctionRole,
            (restakingRewardsDepositorProxy, restakingRewardsDepositorSelectors, ROLE_ID_RESTAKING_REWARDS_DEPOSITOR)
        );

        calldatas[2] =
            abi.encodeCall(AccessManager.grantRole, (ROLE_ID_RESTAKING_REWARDS_DEPOSITOR, operationsMultisig, 0));

        calldatas[3] = abi.encodeCall(
            AccessManager.labelRole, (ROLE_ID_RESTAKING_REWARDS_DEPOSITOR, "Restaking Rewards Depositor")
        );

        bytes4[] memory opsMultisigSelectors = new bytes4[](2);
        opsMultisigSelectors[0] = PufferRestakingRewardsDepositor.removeRestakingOperator.selector;
        opsMultisigSelectors[1] = PufferRestakingRewardsDepositor.addRestakingOperators.selector;

        calldatas[4] = abi.encodeCall(
            AccessManager.setTargetFunctionRole,
            (restakingRewardsDepositorProxy, opsMultisigSelectors, ROLE_ID_OPERATIONS_MULTISIG)
        );

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        return encodedMulticall;
    }
}
