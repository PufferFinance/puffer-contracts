// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_DAO } from "../../script/Roles.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";

contract GenerateSlashingELCalldata is Script {
    function run(address pufferModuleManagerProxy) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](1);

        bytes4[] memory daoSelectors = new bytes4[](2);
        daoSelectors[0] = PufferModuleManager.callRegisterOperatorToAVS.selector;
        daoSelectors[1] = PufferModuleManager.callDeregisterOperatorFromAVS.selector;

        calldatas[0] =
            abi.encodeCall(AccessManager.setTargetFunctionRole, (pufferModuleManagerProxy, daoSelectors, ROLE_ID_DAO));

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        return encodedMulticall;
    }
}
