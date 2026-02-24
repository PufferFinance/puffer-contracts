// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { PermissionedOracle } from "../../src/PermissionedOracle.sol";
import {
    ROLE_ID_DAO,
    ROLE_ID_OPERATIONS_PAYMASTER,
    ROLE_ID_PUFFER_PROTOCOL,
    ROLE_ID_VALIDATOR_EJECTOR,
    ROLE_ID_PERMISSIONED_OPERATOR,
    ROLE_ID_PERMISSIONED_ETH_MANAGER
} from "../../script/Roles.sol";

/**
 * @title GeneratePermissionedModuleCalldata
 * @author Puffer Finance
 * @notice Generates the AccessManager calldata to set up access control for the permissioned
 *         validator feature: PermissionedOracle, new PufferProtocol functions, and new
 *         PufferModuleManager functions.
 *
 *         The returned calldata is queued and executed through the Timelock:
 *         1. timelock.queueTransaction(address(accessManager), encodedMulticall, 1)
 *         2. ... 7 days later ...
 *         3. timelock.executeTransaction(address(accessManager), encodedMulticall, 1)
 *
 *         forge script script/AccessManagerMigrations/09_GeneratePermissionedModuleCalldata.s.sol \
 *             --sig 'run(address,address,address)' \
 *             <PUFFER_PROTOCOL_PROXY> <MODULE_MANAGER_PROXY> <PERMISSIONED_ORACLE> \
 *             -vvvv
 */
contract GeneratePermissionedModuleCalldata is Script {
    function run(address pufferProtocol, address moduleManager, address permissionedOracle)
        public
        pure
        returns (bytes memory)
    {
        bytes[] memory calldatas = new bytes[](9);

        // 1. PermissionedOracle: restrict to PUFFER_PROTOCOL role
        calldatas[0] = _setupPermissionedOracleAccess(permissionedOracle);

        // 2. PufferProtocol: DAO-restricted permissioned functions
        calldatas[1] = _setupProtocolDaoAccess(pufferProtocol);

        // 3. PufferProtocol: paymaster-restricted permissioned functions
        calldatas[2] = _setupProtocolPaymasterAccess(pufferProtocol);

        // 4. PufferProtocol: permissioned-operator-restricted functions
        calldatas[3] = _setupProtocolPermissionedOperatorAccess(pufferProtocol);

        // 5. PufferModuleManager: DAO permissioned functions
        calldatas[4] = _setupModuleManagerDaoAccess(moduleManager);

        // 6. PufferModuleManager: paymaster permissioned functions
        calldatas[5] = _setupModuleManagerPaymasterAccess(moduleManager);

        // 7. PufferModuleManager: validator ejector permissioned functions
        calldatas[6] = _setupModuleManagerEjectorAccess(moduleManager);

        // 8. PufferModuleManager: dedicated role for ETH transfers out of permissioned modules
        //    Overrides the prior DAO assignment from SetupAccess — grant ROLE_ID_PERMISSIONED_ETH_MANAGER
        //    to the appropriate multisig/address via a separate DAO tx after this migration.
        calldatas[7] = _setupModuleManagerEthManagerAccess(moduleManager);

        // 9. Label the new role
        calldatas[8] = abi.encodeWithSelector(
            AccessManager.labelRole.selector, ROLE_ID_PERMISSIONED_ETH_MANAGER, "Permissioned ETH Manager"
        );

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));
        return encodedMulticall;
    }

    /**
     * @dev PermissionedOracle functions are restricted to PUFFER_PROTOCOL (called by PufferProtocol).
     */
    function _setupPermissionedOracleAccess(address permissionedOracle) internal pure returns (bytes memory) {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PermissionedOracle.provisionValidator.selector;
        selectors[1] = PermissionedOracle.exitValidator.selector;
        selectors[2] = PermissionedOracle.adjustLockedEth.selector;

        return abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, permissionedOracle, selectors, ROLE_ID_PUFFER_PROTOCOL
        );
    }

    /**
     * @dev PufferProtocol DAO functions: module creation (matches createPufferModule pattern).
     */
    function _setupProtocolDaoAccess(address pufferProtocol) internal pure returns (bytes memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PufferProtocol.createPermissionedModule.selector;

        return
            abi.encodeWithSelector(AccessManager.setTargetFunctionRole.selector, pufferProtocol, selectors, ROLE_ID_DAO);
    }

    /**
     * @dev PufferProtocol paymaster functions: provisioning and exit handling
     *      (matches provisionNode / batchHandleWithdrawals / skipProvisioning pattern).
     */
    function _setupProtocolPaymasterAccess(address pufferProtocol) internal pure returns (bytes memory) {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PufferProtocol.provisionPermissionedValidator.selector;
        selectors[1] = PufferProtocol.handlePermissionedValidatorExit.selector;
        selectors[2] = PufferProtocol.skipPermissionedProvisioning.selector;

        return abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, pufferProtocol, selectors, ROLE_ID_OPERATIONS_PAYMASTER
        );
    }

    /**
     * @dev PufferProtocol permissioned operator functions: validator key registration.
     *      ROLE_ID_PERMISSIONED_OPERATOR (29) must be granted to operator addresses separately.
     */
    function _setupProtocolPermissionedOperatorAccess(address pufferProtocol) internal pure returns (bytes memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PufferProtocol.registerPermissionedValidatorKey.selector;

        return abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, pufferProtocol, selectors, ROLE_ID_PERMISSIONED_OPERATOR
        );
    }

    /**
     * @dev PufferModuleManager DAO functions for permissioned modules
     *      (matches callDelegateTo / callUndelegate / callSetProofSubmitter / callSetClaimerFor pattern).
     */
    function _setupModuleManagerDaoAccess(address moduleManager) internal pure returns (bytes memory) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = PufferModuleManager.callDelegateToPermissioned.selector;
        selectors[1] = PufferModuleManager.callUndelegatePermissioned.selector;
        selectors[2] = PufferModuleManager.callSetProofSubmitterPermissioned.selector;
        selectors[3] = PufferModuleManager.callSetClaimerForPermissioned.selector;

        return
            abi.encodeWithSelector(AccessManager.setTargetFunctionRole.selector, moduleManager, selectors, ROLE_ID_DAO);
    }

    /**
     * @dev PufferModuleManager paymaster functions for permissioned modules:
     *      queue/complete withdrawals, withdraw non-restaked ETH, trigger non-restaked withdrawals.
     */
    function _setupModuleManagerPaymasterAccess(address moduleManager) internal pure returns (bytes memory) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = PufferModuleManager.callQueueWithdrawalsPermissioned.selector;
        selectors[1] = PufferModuleManager.callCompleteQueuedWithdrawalsPermissioned.selector;
        selectors[2] = PufferModuleManager.withdrawNonRestakedETH.selector;
        selectors[3] = PufferModuleManager.triggerNonRestakedValidatorWithdrawals.selector;

        return abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, moduleManager, selectors, ROLE_ID_OPERATIONS_PAYMASTER
        );
    }

    /**
     * @dev PufferModuleManager validator ejector functions for permissioned modules.
     */
    function _setupModuleManagerEjectorAccess(address moduleManager) internal pure returns (bytes memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PufferModuleManager.triggerRestakedValidatorsExit.selector;

        return abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, moduleManager, selectors, ROLE_ID_VALIDATOR_EJECTOR
        );
    }

    /**
     * @dev transferPermissionedModuleETH gets its own dedicated role because it directly controls
     *      outbound ETH flow from permissioned modules and deserves independent access governance.
     */
    function _setupModuleManagerEthManagerAccess(address moduleManager) internal pure returns (bytes memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PufferModuleManager.transferPermissionedModuleETH.selector;

        return abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, moduleManager, selectors, ROLE_ID_PERMISSIONED_ETH_MANAGER
        );
    }
}
