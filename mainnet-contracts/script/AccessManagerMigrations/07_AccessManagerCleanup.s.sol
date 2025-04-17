// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

// - Guardian role 88 is unused
// - Puffer Oracle role 999 is unused
// - Reward Watcher 21 role is unused
// - Conflicting role ID 25::Granted VT pricer role 25 to MergedAdapterWithoutRoundsPufStakingV1 proxy - 0xf9dfbf71f2d9c8a4e565e1346aeb2c3e1dc765de
//     - Currently Active on ValidatorTicketPricer - 0x9830ad1bd5cf73640e253edf97dee3791c4a53c3

// - Add PufferOracleV2 - 0x8eFd1Dc43AD073232F3e2924e22F173879119489 to ACL?
//     - There is another PufferOracle 0x0be2ae0edbebb517541df217ef0074fc9a9e994f also
//     - PufferOracleV2 has PufferProtocol 1234 role for few functions like provisionNode and exitValidators
//     - Granted function role on v2 on setMintPrice

// - DUPLICATE OperationsCoordinator 0xe6d798165a32f37927af20d7ccb1f80fb731a3c0
//     - Original OperationsCoordinator- 0x3fee92765f5cf8f9909a3c89f4907ea5e1cd9bf7
//     - Granted Operations Coordinator 24 role to duplicate one
//     - Granted function role setValidatorTicketMintPrice on duplicate one

// - Upgrader role 1 is granted to 0x0000000000000000000000000000000000000000 contract for upgradeToAndCall(address,bytes) function
// - Lockbox no address on L1?

// TODO:

// create a PR to do cleanup & remove unused roles from the code
// DONE - fix the conflict for role 25 by creating a new role
// DONE - create a migration script like 06_AccessManagerCleanup.s.sol
// DONE - that script should revoke any roles from  the contracts that we don't use anymore (oracle, operations coordinator)

// DONE - ROLE_ID_LOCKBOX seems unused as well.
// on xPufETH there is `setLockbox` which is restricted to DAO, we don't need this role anymore.

// Upgrader role is useless as well, we should revoke it

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_OPERATIONS_COORDINATOR } from "../../script/Roles.sol";
import { DeployerHelper } from "../../script/DeployerHelper.s.sol";
import { console } from "forge-std/console.sol";
import { PufferWithdrawalManager } from "../../src/PufferWithdrawalManager.sol";
import { ROLE_ID_VT_PRICER, ROLE_ID_WITHDRAWAL_FINALIZER } from "../../script/Roles.sol";

contract AccessManagerCleanup is DeployerHelper {
    function run() public view {
        address duplicateOperationsCoordinator = 0xe6d798165A32F37927AF20D7Ccb1f80fB731a3C0;
        address withdrawalManagerProxy = _getPufferWithdrawalManager();

        address paymaster = _getPaymaster();
        address withdrawalFinalizer = _getOPSMultisig();
        address communityMultisig = _getCommunityMultisig();

        uint64 ROLE_ID_UPGRADER = 1;

        // ------------ 1. Revoke existing ROLE_ID_WITHDRAWAL_FINALIZER roles and re-grant as we have changed the role ID which was 25 earlier and now 27 ------------
        bytes[] memory calldatas = new bytes[](9);

        // 1.1 set target role for finalizeWithdrawals
        bytes4[] memory paymasterSelectors = new bytes4[](1);
        paymasterSelectors[0] = PufferWithdrawalManager.finalizeWithdrawals.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            withdrawalManagerProxy,
            paymasterSelectors,
            ROLE_ID_WITHDRAWAL_FINALIZER
        );
        // 1.2 revoke existing roles
        calldatas[1] =
            abi.encodeWithSelector(AccessManager.revokeRole.selector, ROLE_ID_WITHDRAWAL_FINALIZER, paymaster);
        calldatas[2] =
            abi.encodeWithSelector(AccessManager.revokeRole.selector, ROLE_ID_WITHDRAWAL_FINALIZER, withdrawalFinalizer);

        // 1.3 grant finalizer roles to paymaster and withdrawalFinalizer addresses
        calldatas[3] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_WITHDRAWAL_FINALIZER, paymaster, 0);

        calldatas[4] = abi.encodeWithSelector(
            AccessManager.grantRole.selector, ROLE_ID_WITHDRAWAL_FINALIZER, withdrawalFinalizer, 0
        );

        // 1.4 label role
        calldatas[5] = abi.encodeWithSelector(
            AccessManager.labelRole.selector, ROLE_ID_WITHDRAWAL_FINALIZER, "Withdrawal Finalizer"
        );

        // 1.5 label role 25 as VT pricer
        calldatas[6] =
            abi.encodeWithSelector(AccessManager.labelRole.selector, ROLE_ID_VT_PRICER, "Validator Ticket Pricer");
        // -------------------

        // 2. Revoke Operations Coordinator role from duplicate contract
        // 2.1 revoke role from duplicate contract
        calldatas[7] = abi.encodeWithSelector(
            AccessManager.revokeRole.selector, ROLE_ID_OPERATIONS_COORDINATOR, duplicateOperationsCoordinator
        );
        // NOTE: this duplicate contract has setValidatorTicketMintPrice function which has been granted Operations Paymaster (ID: 23) role

        // 3. Revoke PufferOracle role from PufferOracleV2
        // NOTE:  PufferOracleV2 has PufferProtocol 1234 role for few functions like provisionNode and exitValidators, so we can skip it, or can change it some unaccessible role?

        // 4. revoke uint64 constant ROLE_ID_UPGRADER = 1; from Community Multisig	0x446d4d6b26815f9ba78b5d454e303315d586cb2a
        calldatas[8] = abi.encodeWithSelector(AccessManager.revokeRole.selector, ROLE_ID_UPGRADER, communityMultisig);

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        console.log("Timelock -> AccessManager");
        console.log("AccessManagerCleanup calldatas:");
        console.logBytes(encodedMulticall);
    }
}
