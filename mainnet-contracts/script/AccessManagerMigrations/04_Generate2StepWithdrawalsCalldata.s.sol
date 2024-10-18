// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import {
    ROLE_ID_WITHDRAWAL_FINALIZER,
    PUBLIC_ROLE,
    ROLE_ID_DAO,
    ROLE_ID_VAULT_WITHDRAWER,
    ROLE_ID_PUFETH_BURNER,
    ROLE_ID_OPERATIONS_MULTISIG
} from "../../script/Roles.sol";
import { PufferWithdrawalManager } from "../../src/PufferWithdrawalManager.sol";
import { PufferVaultV2 } from "../../src/PufferVaultV2.sol";

contract Generate2StepWithdrawalsCalldata is Script {
    function run(
        address pufferVaultProxy,
        address pufferProtocolProxy,
        address withdrawalManagerProxy,
        address paymaster,
        address withdrawalFinalizer
    ) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](15);

        bytes4[] memory paymasterSelectors = new bytes4[](1);
        paymasterSelectors[0] = PufferWithdrawalManager.finalizeWithdrawals.selector;
        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            withdrawalManagerProxy,
            paymasterSelectors,
            ROLE_ID_WITHDRAWAL_FINALIZER
        );

        // Everybody can complete queued withdrawals
        bytes4[] memory publicSelectors = new bytes4[](3);
        publicSelectors[0] = PufferWithdrawalManager.completeQueuedWithdrawal.selector;
        publicSelectors[1] = PufferWithdrawalManager.requestWithdrawal.selector;
        publicSelectors[2] = PufferWithdrawalManager.requestWithdrawalWithPermit.selector;
        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, withdrawalManagerProxy, publicSelectors, PUBLIC_ROLE
        );

        calldatas[2] = abi.encodeWithSelector(
            AccessManager.grantRole.selector, ROLE_ID_VAULT_WITHDRAWER, withdrawalManagerProxy, 0
        );

        calldatas[3] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_WITHDRAWAL_FINALIZER, paymaster, 0);

        calldatas[4] = abi.encodeWithSelector(
            AccessManager.grantRole.selector, ROLE_ID_WITHDRAWAL_FINALIZER, withdrawalFinalizer, 0
        );

        calldatas[5] = abi.encodeWithSelector(
            AccessManager.labelRole.selector, ROLE_ID_VAULT_WITHDRAWER, "Puffer Vault Withdrawer"
        );

        calldatas[6] = abi.encodeWithSelector(
            AccessManager.labelRole.selector, ROLE_ID_WITHDRAWAL_FINALIZER, "Withdrawal Finalizer"
        );

        calldatas[7] = abi.encodeWithSelector(AccessManager.labelRole.selector, ROLE_ID_PUFETH_BURNER, "pufETH Burner");

        bytes4[] memory vaultWithdrawerSelectors = new bytes4[](1);
        vaultWithdrawerSelectors[0] = PufferVaultV2.transferETH.selector;

        calldatas[8] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            pufferVaultProxy,
            vaultWithdrawerSelectors,
            ROLE_ID_VAULT_WITHDRAWER
        );

        bytes4[] memory burnerSelectors = new bytes4[](1);
        burnerSelectors[0] = PufferVaultV2.burn.selector;

        calldatas[9] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, pufferVaultProxy, burnerSelectors, ROLE_ID_PUFETH_BURNER
        );

        calldatas[10] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_PUFETH_BURNER, withdrawalManagerProxy, 0);

        bytes4[] memory daoSelectors = new bytes4[](1);
        daoSelectors[0] = PufferWithdrawalManager.changeMaxWithdrawalAmount.selector;
        calldatas[11] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, withdrawalManagerProxy, daoSelectors, ROLE_ID_DAO
        );

        // in AccessManager contract, one selector can be assigned to only one role for a target contract
        // see `AccessManager._setTargetFunctionRole` function
        // creation of this new `ROLE_ID_VAULT_WITHDRAWER` and assigning the `PufferVaultV2.transferETH` selector to it
        // would revoke that ability from the original `ROLE_ID_PUFFER_PROTOCOL`
        // that's why we need to grant the `ROLE_ID_VAULT_WITHDRAWER` and `ROLE_ID_PUFETH_BURNER` to the pufferProtocolProxy
        calldatas[12] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_VAULT_WITHDRAWER, pufferProtocolProxy, 0);

        calldatas[13] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_PUFETH_BURNER, pufferProtocolProxy, 0);

        bytes4[] memory opsSelectors = new bytes4[](1);
        opsSelectors[0] = PufferWithdrawalManager.returnExcessETHToVault.selector;
        calldatas[14] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            withdrawalManagerProxy,
            opsSelectors,
            ROLE_ID_OPERATIONS_MULTISIG
        );

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        return encodedMulticall;
    }
}
