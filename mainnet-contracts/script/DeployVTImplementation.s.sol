// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { ValidatorTicket } from "../src/ValidatorTicket.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { IPufferOracle } from "../src/interface/IPufferOracle.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";

/**
 * // Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/DeployVTImplementation.s.sol:DeployVTImplementation --rpc-url=$RPC_URL --private-key $PK --vvvv
 *
 *       `forge cache clean`
 *       forge script script/DeployVTImplementation.s.sol:DeployVTImplementation --rpc-url=$RPC_URL --private-key $PK --broadcast
 */
contract DeployVTImplementation is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        // Implementation of ValidatorTicket
        ValidatorTicket validatorTicketImplementation;
        validatorTicketImplementation = new ValidatorTicket({
            guardianModule: payable(address(_getGuardianModule())),
            treasury: payable(_getTreasury()),
            pufferVault: payable(_getPufferVault()),
            pufferOracle: IPufferOracle(address(_getPufferOracle())),
            operationsMultisig: _getOPSMultisig()
        });

        //@todo Double check reinitialization
        _consoleLogOrUpgradeUUPS({
            proxyTarget: _getValidatorTicket(),
            implementation: address(validatorTicketImplementation),
            data: "",
            contractName: "ValidatorTicketImplementation"
        });
    }
}
