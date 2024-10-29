// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { ValidatorTicket } from "../src/ValidatorTicket.sol";
import { GenerateValidatorTicketCalldata } from "./AccessManagerMigrations/05_GenerateValidatorTicketCalldata.s.sol";
import { IPufferOracle } from "../src/interface/IPufferOracle.sol";

/**
 * forge script script/UpgradeValidatorTicket.s.sol:UpgradeValidatorTicket --rpc-url=$RPC_URL --private-key $PK
 * add --slow if deploying to a mainnet fork like tenderly
 */
contract UpgradeValidatorTicket is DeployerHelper {
    ValidatorTicket public validatorTicket;
    bytes public encodedCalldata;

    function run() public {
        GenerateValidatorTicketCalldata calldataGenerator = new GenerateValidatorTicketCalldata();

        vm.startBroadcast();

        ValidatorTicket validatorTicketImpl = new ValidatorTicket({
            guardianModule: payable(address(_getGuardianModule())),
            treasury: payable(_getTreasury()),
            pufferVault: payable(_getPufferVault()),
            pufferOracle: IPufferOracle(address(_getPufferOracle()))
        });

        validatorTicket = ValidatorTicket(payable(_getValidatorTicket()));

        vm.label(address(validatorTicket), "ValidatorTicketProxy");
        vm.label(address(validatorTicketImpl), "ValidatorTicketImplementation");

        // Upgrade proxy
        _consoleLogOrUpgradeUUPS({
            proxyTarget: _getValidatorTicket(),
            implementation: address(validatorTicketImpl),
            data: "",
            contractName: "ValidatorTicketImplementation"
        });

        encodedCalldata = calldataGenerator.run(address(validatorTicket));

        console.log("Queue from Timelock -> AccessManager", _getAccessManager());
        console.logBytes(encodedCalldata);

        // If on testnet, execute the access control changes directly
        if (block.chainid == holesky) {
            (bool success,) = address(_getAccessManager()).call(encodedCalldata);
            console.log("AccessManager.call success", success);
            require(success, "AccessManager.call failed");

            // Check if purchaseValidatorTicketWithPufETH function exists after upgrade
            (bool functionExists,) = address(validatorTicket).call(
                abi.encodeWithSignature("purchaseValidatorTicketWithPufETH(address,uint256)")
            );
            console.log("purchaseValidatorTicketWithPufETH function exists:", functionExists);
            require(functionExists, "purchaseValidatorTicketWithPufETH function does not exist after upgrade");
        }

        vm.stopBroadcast();
    }
}
