// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { ValidatorTicketPricer } from "../src/ValidatorTicketPricer.sol";
import { PufferOracleV2 } from "../src/PufferOracleV2.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import {
    ROLE_ID_VT_PRICER,
    ROLE_ID_OPERATIONS_COORDINATOR,
    ROLE_ID_OPERATIONS_MULTISIG,
    ROLE_ID_DAO,
    PUBLIC_ROLE
} from "./Roles.sol";

/**
 * // Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/DeployVTPricer.s.sol:DeployVTPricer --rpc-url $RPC_URL --account puffer
 *
 *       forge cache clean
 *
 *       forge script script/DeployVTPricer.s.sol:DeployVTPricer --rpc-url $RPC_URL --account puffer --broadcast
 */
contract DeployVTPricer is Script {
    ValidatorTicketPricer validatorTicketPricer;

    address ACCCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;
    address ORACLE = 0x0BE2aE0edbeBb517541DF217EF0074FC9a9e994f;
    address VT_PRICER = 0x65d2dd7A66a2733a36559fE900A236280A05FBD6; // Puffer Backend

    function run() public {
        vm.startBroadcast();

        validatorTicketPricer =
            new ValidatorTicketPricer({ oracle: PufferOracleV2(address(ORACLE)), accessManager: ACCCESS_MANAGER });

        console.log("Deployed VT Pricer:", address(validatorTicketPricer));

        _generateAccessManagerCallData();
    }

    function _generateAccessManagerCallData() internal view {
        bytes[] memory calldatas = new bytes[](6);

        bytes4[] memory operationsSelectors = new bytes4[](2);
        operationsSelectors[0] = ValidatorTicketPricer.setDailyMevPayoutsChangeToleranceBps.selector;
        operationsSelectors[1] = ValidatorTicketPricer.setDailyConsensusRewardsChangeToleranceBps.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(validatorTicketPricer),
            operationsSelectors,
            ROLE_ID_OPERATIONS_MULTISIG
        );

        bytes4[] memory daoSelectors = new bytes4[](1);
        daoSelectors[0] = ValidatorTicketPricer.setDiscountRate.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, validatorTicketPricer, daoSelectors, ROLE_ID_DAO
        );

        bytes4[] memory vtPricerSelectors = new bytes4[](3);
        vtPricerSelectors[0] = ValidatorTicketPricer.setDailyMevPayouts.selector;
        vtPricerSelectors[1] = ValidatorTicketPricer.setDailyConsensusRewards.selector;
        vtPricerSelectors[2] = ValidatorTicketPricer.setDailyRewardsAndPostMintPrice.selector;

        calldatas[2] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(validatorTicketPricer),
            vtPricerSelectors,
            ROLE_ID_VT_PRICER
        );

        bytes4[] memory publicSelectors = new bytes4[](1);
        publicSelectors[0] = ValidatorTicketPricer.postMintPrice.selector;

        calldatas[3] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(validatorTicketPricer), publicSelectors, PUBLIC_ROLE
        );

        // ROLE_ID_OPERATIONS_COORDINATOR is the only role allowed to call Oracle.setMintPrice(), we need to give this role
        // to this newly deployed contract
        calldatas[4] = abi.encodeWithSelector(
            AccessManager.grantRole.selector, ROLE_ID_OPERATIONS_COORDINATOR, address(validatorTicketPricer), 0
        );

        calldatas[5] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_VT_PRICER, VT_PRICER, 0);

        bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));

        console.log("AccessManager multicall calldata:");
        console.logBytes(multicallData);
    }
}
