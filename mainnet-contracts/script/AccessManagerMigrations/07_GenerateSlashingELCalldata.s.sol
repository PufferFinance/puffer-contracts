// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_DAO, ROLE_ID_OPERATIONS_PAYMASTER } from "../../script/Roles.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";

// forge script script/AccessManagerMigrations/07_GenerateSlashingELCalldata.s.sol:GenerateSlashingELCalldata -vvvv --sig "run(address)(bytes memory)" PUFFER_MODULE_MANAGER_PROXY_ADDRESS
contract GenerateSlashingELCalldata is Script {
    function run(address pufferModuleManagerProxy) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](2);

        bytes4[] memory daoSelectors = new bytes4[](9);
        daoSelectors[0] = PufferModuleManager.callSetClaimerFor.selector;
        daoSelectors[1] = PufferModuleManager.callSetProofSubmitter.selector;
        daoSelectors[2] = PufferModuleManager.createNewRestakingOperator.selector;
        daoSelectors[3] = PufferModuleManager.callDelegateTo.selector;
        daoSelectors[4] = PufferModuleManager.callUndelegate.selector;
        daoSelectors[5] = PufferModuleManager.callRegisterOperatorToAVS.selector;
        daoSelectors[6] = PufferModuleManager.customExternalCall.selector;
        daoSelectors[7] = PufferModuleManager.callDeregisterOperatorFromAVS.selector;
        daoSelectors[8] = PufferModuleManager.updateAVSRegistrationSignatureProof.selector;

        calldatas[0] =
            abi.encodeCall(AccessManager.setTargetFunctionRole, (pufferModuleManagerProxy, daoSelectors, ROLE_ID_DAO));

        bytes4[] memory paymasterSelectors = new bytes4[](3);
        paymasterSelectors[0] = PufferModuleManager.callCompleteQueuedWithdrawals.selector;
        paymasterSelectors[1] = PufferModuleManager.transferRewardsToTheVault.selector;
        paymasterSelectors[2] = PufferModuleManager.callQueueWithdrawals.selector;

        calldatas[1] = abi.encodeCall(
            AccessManager.setTargetFunctionRole,
            (pufferModuleManagerProxy, paymasterSelectors, ROLE_ID_OPERATIONS_PAYMASTER)
        );

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        return encodedMulticall;
    }
}
