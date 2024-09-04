// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { console } from "forge-std/console.sol";
import { ROLE_ID_DAO } from "../../script/Roles.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";

/**
 * @title GenerateAccessManagerCalldata2
 * @author Puffer Finance
 * @notice Generates the AccessManager call data to setup the public access
 * The returned calldata is queued and executed by the Operations Multisig
 * 1. timelock.queueTransaction(address(accessManager), encodedMulticall, 1)
 * 2. ... 7 days later ...
 * 3. timelock.executeTransaction(address(accessManager), encodedMulticall, 1)
 */
contract GenerateAccessManagerCalldata2 is Script {
    function run(address moduleManager) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](1);

        bytes4[] memory daoSelectors = new bytes4[](3);
        daoSelectors[0] = PufferModuleManager.callSetClaimerFor.selector;
        daoSelectors[1] = PufferModuleManager.callStartCheckpoint.selector;
        daoSelectors[2] = PufferModuleManager.callSetProofSubmitter.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, moduleManager, daoSelectors, ROLE_ID_DAO
        );

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        // console.log("GenerateAccessManagerCallData:");
        // console.logBytes(encodedMulticall);

        return encodedMulticall;
    }
}
