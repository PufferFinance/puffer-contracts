// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_DAO, ROLE_ID_REVENUE_DEPOSITOR, ROLE_ID_OPERATIONS_MULTISIG } from "../../script/Roles.sol";
import { PufferRevenueDepositor } from "../../src/PufferRevenueDepositor.sol";
import { RestakingOperatorController } from "../../src/RestakingOperatorController.sol";

contract GenerateRestakingOperatorCalldata is Script {
    function run(address restakingOperatorController) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](1);

        bytes4[] memory daoSelectors = new bytes4[](2);
        daoSelectors[0] = RestakingOperatorController.setOperatorOwner.selector;
        daoSelectors[1] = RestakingOperatorController.setAllowedSelector.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, restakingOperatorController, daoSelectors, ROLE_ID_DAO
        );

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        // console.log("GenerateAccessManagerCallData:");
        // console.logBytes(encodedMulticall);

        return encodedMulticall;
    }
}
