// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { console } from "forge-std/console.sol";
import { ROLE_ID_OPERATIONS_PAYMASTER, PUBLIC_ROLE, ROLE_ID_PUFFER_PROTOCOL } from "../../script/Roles.sol";
import { PufferWithdrawalManager } from "../../src/PufferWithdrawalManager.sol";
import { PufferVaultV2 } from "../../src/PufferVaultV2.sol";

contract Generate2StepWithdrawalsCalldata is Script {
    function run(address withdrawalManagerProxy, address pufferVault) public view returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](4);

        bytes4[] memory paymasterSelectors = new bytes4[](1);
        paymasterSelectors[0] = PufferWithdrawalManager.finalizeWithdrawals.selector;
        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            withdrawalManagerProxy,
            paymasterSelectors,
            ROLE_ID_OPERATIONS_PAYMASTER
        );

        bytes4[] memory publicSelectors = new bytes4[](1);
        publicSelectors[0] = PufferWithdrawalManager.completeQueuedWithdrawal.selector;
        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, withdrawalManagerProxy, publicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory pufferselectors = new bytes4[](1);
        pufferselectors[0] = PufferVaultV2.transferETH.selector;
        calldatas[2] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, pufferVault, pufferselectors, ROLE_ID_PUFFER_PROTOCOL
        );

        calldatas[3] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_PUFFER_PROTOCOL, withdrawalManagerProxy, 0);

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        return encodedMulticall;
    }
}
