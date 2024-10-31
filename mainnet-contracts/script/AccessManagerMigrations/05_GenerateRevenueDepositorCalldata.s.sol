// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_DAO, ROLE_ID_REVENUE_DEPOSITOR } from "../../script/Roles.sol";
import { PufferRevenueDepositor } from "../../src/PufferRevenueDepositor.sol";

contract GenerateRevenueDepositorCalldata is Script {
    function run(address revenueDepositorProxy, address operationsMultisig) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](4);

        bytes4[] memory daoSelectors = new bytes4[](1);
        daoSelectors[0] = PufferRevenueDepositor.setRewardsDistributionWindow.selector;

        calldatas[0] =
            abi.encodeCall(AccessManager.setTargetFunctionRole, (revenueDepositorProxy, daoSelectors, ROLE_ID_DAO));

        bytes4[] memory revenueDepositorSelectors = new bytes4[](1);
        revenueDepositorSelectors[0] = PufferRevenueDepositor.depositRevenue.selector;

        calldatas[1] = abi.encodeCall(
            AccessManager.setTargetFunctionRole,
            (revenueDepositorProxy, revenueDepositorSelectors, ROLE_ID_REVENUE_DEPOSITOR)
        );

        calldatas[2] = abi.encodeCall(AccessManager.grantRole, (ROLE_ID_REVENUE_DEPOSITOR, operationsMultisig, 0));

        calldatas[3] = abi.encodeCall(AccessManager.labelRole, (ROLE_ID_REVENUE_DEPOSITOR, "Revenue Depositor"));

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        return encodedMulticall;
    }
}
