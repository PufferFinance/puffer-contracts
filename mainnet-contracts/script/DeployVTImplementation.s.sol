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

/**
 * // Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/DeployVTImplementation.s.sol:DeployVTImplementation --rpc-url=$RPC_URL --private-key $PK --vvvv
 *
 *       `forge cache clean`
 *       forge script script/DeployVTImplementation.s.sol:DeployVTImplementation --rpc-url=$RPC_URL --private-key $PK --broadcast
 */
contract DeployVTImplementation is Script {
    ValidatorTicket validatorTicketImplementation;

    address PUFFER_VAULT = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    address TREASURY = 0x946Ae7b21de3B0793Bb469e263517481B74A6950;

    address GUARDIAN_MODULE = 0xa95aa41bBa980Eb7a80e7bfF4F6218244C723f57;
    address ORACLE = 0x785a54316Af8Cb61b16a82a3f60c08A18425fA86;

    function run() public {
        vm.startBroadcast();

        // Implementation of ValidatorTicket
        validatorTicketImplementation = new ValidatorTicket({
            guardianModule: payable(address(GUARDIAN_MODULE)),
            treasury: payable(TREASURY),
            pufferVault: payable(PUFFER_VAULT),
            pufferOracle: IPufferOracle(address(ORACLE))
        });
    }
}
