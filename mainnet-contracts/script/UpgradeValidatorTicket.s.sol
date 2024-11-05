// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { ValidatorTicket } from "../src/ValidatorTicket.sol";
import { GenerateValidatorTicketCalldata } from "./AccessManagerMigrations/05_GenerateValidatorTicketCalldata.s.sol";
import { IPufferOracle } from "../src/interface/IPufferOracle.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * forge script script/UpgradeValidatorTicket.s.sol:UpgradeValidatorTicket --rpc-url=$RPC_URL --private-key $PK
 * add --slow if deploying to a mainnet fork like tenderly
 */
contract UpgradeValidatorTicket is DeployerHelper {
    ValidatorTicket public validatorTicket;
    bytes public upgradeCallData;
    bytes public accessManagerCallData;

    function run() public {
        GenerateValidatorTicketCalldata calldataGenerator = new GenerateValidatorTicketCalldata();

        vm.startBroadcast();

        ValidatorTicket validatorTicketImpl = new ValidatorTicket({
            guardianModule: payable(address(_getGuardianModule())),
            treasury: payable(_getTreasury()),
            pufferVault: payable(_getPufferVault()),
            pufferOracle: IPufferOracle(address(_getPufferOracle())),
            operationsMultisig: _getOPSMultisig()
        });

        validatorTicket = ValidatorTicket(payable(_getValidatorTicket()));

        vm.label(address(validatorTicket), "ValidatorTicketProxy");
        vm.label(address(validatorTicketImpl), "ValidatorTicketImplementation");

        // Upgrade on mainnet
        upgradeCallData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(validatorTicketImpl), ""));
        console.log("Queue TX From Timelock to -> ValidatorTicketProxy", _getValidatorTicket());
        console.logBytes(upgradeCallData);
        console.log("================================================");
        accessManagerCallData = calldataGenerator.run(address(validatorTicket));

        console.log("Queue from Timelock -> AccessManager", _getAccessManager());
        console.logBytes(accessManagerCallData);

        // If on testnet, upgrade and execute access control changes directly
        if (block.chainid == holesky) {
            // upgrade to implementation
            AccessManager(_getAccessManager()).execute(
                address(validatorTicket),
                abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(validatorTicketImpl), ""))
            );

            // execute access control changes
            (bool success,) = address(_getAccessManager()).call(accessManagerCallData);
            console.log("AccessManager.call success", success);
            require(success, "AccessManager.call failed");
        }
        vm.stopBroadcast();
    }
}
