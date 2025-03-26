// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_OPERATOR_AVS_SOCKET_UPDATER } from "../../script/Roles.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { console } from "forge-std/console.sol";
import { DeployerHelper } from "script/DeployerHelper.s.sol";

/**
 * @title GenerateOperatorAVSSocketRoleCalldata
 * @author Puffer Finance
 * @notice Generates the call data to setup the Operator AVS Socket Updater role
 * The returned calldata is queued and executed by the Operations Multisig
 * 1. timelock.queueTransaction(address(accessManager), encodedMulticall, 1)
 * 2. ... 7 days later ...
 * 3. timelock.executeTransaction(address(accessManager), encodedMulticall, 1)
 *
 * forge script script/AccessManagerMigrations/07_GenerateOperatorAVSSocketRoleCalldata.s.sol:GenerateOperatorAVSSocketRoleCalldata --chain mainnet
 * ```
 */
contract GenerateOperatorAVSSocketRoleCalldata is DeployerHelper {
    function run() public view returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](3);

        bytes4[] memory operatorAVSSocketUpdaterSelectors = new bytes4[](1);
        operatorAVSSocketUpdaterSelectors[0] = PufferModuleManager.callUpdateOperatorAVSSocket.selector;

        calldatas[0] = abi.encodeCall(
            AccessManager.setTargetFunctionRole,
            (_getPufferModuleManager(), operatorAVSSocketUpdaterSelectors, ROLE_ID_OPERATOR_AVS_SOCKET_UPDATER)
        );

        calldatas[1] = abi.encodeCall(
            AccessManager.labelRole, (ROLE_ID_OPERATOR_AVS_SOCKET_UPDATER, "Operator AVS Socket Updater")
        );

        // Grant role to multisig specific to the Operator AVS Socket Updater
        calldatas[2] = abi.encodeCall(
            AccessManager.grantRole, (ROLE_ID_OPERATOR_AVS_SOCKET_UPDATER, _getOperatorAVSSocketUpdaterMultisig(), 0)
        );

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));
        console.logBytes(encodedMulticall);
        return encodedMulticall;
    }
}
