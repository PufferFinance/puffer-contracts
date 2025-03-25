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
 * forge script script/AccessManagerMigrations/07_GenerateOperatorAVSSocketRoleCalldata.s.sol:GenerateOperatorAVSSocketRoleCalldata
 * ```
 */
contract GenerateOperatorAVSSocketRoleCalldata is DeployerHelper {
    function run() public view returns (bytes memory) {
        // Grant role to these addresses:
        address[] memory addresses = new address[](5);
        addresses[0] = 0xD70aa9d7280E6FEe89B86f53c0B2A363478D5e94;
        addresses[1] = 0xf061f1FceFa32b3bbD5d18c5A623DB64bfBc107D;
        addresses[2] = 0x6e7646a64324722c971F6a7C5807B65fB6cb7f59;
        addresses[3] = 0x8F97Bf67182122D2f1745216a81724143db97E43;
        addresses[4] = 0x1BfAec64abFddcC8c5dA134880d1E71f3E03689E;

        bytes[] memory calldatas = new bytes[](addresses.length + 2);

        bytes4[] memory operatorAVSSocketUpdaterSelectors = new bytes4[](1);
        operatorAVSSocketUpdaterSelectors[0] = PufferModuleManager.callUpdateOperatorAVSSocket.selector;

        calldatas[0] = abi.encodeCall(
            AccessManager.setTargetFunctionRole,
            (_getPufferModuleManager(), operatorAVSSocketUpdaterSelectors, ROLE_ID_OPERATOR_AVS_SOCKET_UPDATER)
        );

        calldatas[1] = abi.encodeCall(
            AccessManager.labelRole, (ROLE_ID_OPERATOR_AVS_SOCKET_UPDATER, "Operator AVS Socket Updater")
        );

        for (uint256 i = 0; i < addresses.length; i++) {
            calldatas[i + 2] =
                abi.encodeCall(AccessManager.grantRole, (ROLE_ID_OPERATOR_AVS_SOCKET_UPDATER, addresses[i], 0));
        }

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));
        console.log("PufferModuleManager:", _getPufferModuleManager());
        console.logBytes(encodedMulticall);
        return encodedMulticall;
    }
}
