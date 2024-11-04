// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { PUBLIC_ROLE, ROLE_ID_DAO, ROLE_ID_PUFETH_BURNER } from "../../script/Roles.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";

/**
 * @title GenerateValidatorTicketCalldata
 * @author Puffer Finance
 * @notice Generates the call data to setup the ValidatorTicket contract access
 * The returned calldata is queued and executed by the Operations Multisig
 * 1. timelock.queueTransaction(address(accessManager), encodedMulticall, 1)
 * 2. ... 7 days later ...
 * 3. timelock.executeTransaction(address(accessManager), encodedMulticall, 1)
 */
contract GenerateValidatorTicketCalldata is Script {
    function run(address validatorTicketProxy) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](3);

        // Public functions
        bytes4[] memory vtPublicSelectors = new bytes4[](4);
        vtPublicSelectors[0] = ValidatorTicket.burn.selector;
        vtPublicSelectors[1] = ValidatorTicket.purchaseValidatorTicket.selector;
        vtPublicSelectors[2] = ValidatorTicket.purchaseValidatorTicketWithPufETH.selector;
        vtPublicSelectors[3] = ValidatorTicket.purchaseValidatorTicketWithPufETHAndPermit.selector;
        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, validatorTicketProxy, vtPublicSelectors, PUBLIC_ROLE
        );

        // DAO-restricted functions
        bytes4[] memory vtDaoSelectors = new bytes4[](2);
        vtDaoSelectors[0] = ValidatorTicket.setProtocolFeeRate.selector;
        vtDaoSelectors[1] = ValidatorTicket.setGuardiansFeeRate.selector;
        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, validatorTicketProxy, vtDaoSelectors, ROLE_ID_DAO
        );

        // Grant PUFETH_BURNER role to ValidatorTicket
        calldatas[2] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_PUFETH_BURNER, validatorTicketProxy, 0);

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));
        return encodedMulticall;
    }
}
