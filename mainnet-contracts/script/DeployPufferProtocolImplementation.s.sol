// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { PufferVaultV2 } from "../src/PufferVaultV2.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { ValidatorTicket } from "../src/ValidatorTicket.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { IPufferOracleV2 } from "../src/interface/IPufferOracleV2.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";

/**
 * forge script script/DeployPufferProtocolImplementation.s.sol:DeployPufferProtocolImplementation --rpc-url=$RPC_URL --private-key $PK
 */
contract DeployPufferProtocolImplementation is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        address protocolImplementation = address(
            new PufferProtocol({
                pufferVault: PufferVaultV2(payable(_getPufferVault())),
                validatorTicket: ValidatorTicket(address(_getValidatorTicket())),
                guardianModule: GuardianModule(payable(_getGuardianModule())),
                moduleManager: _getPufferModuleManager(),
                oracle: IPufferOracleV2(_getPufferOracle()),
                beaconDepositContract: _getBeaconDepositContract()
            })
        );

        //@todo Double check reinitialization
        _consoleLogOrUpgradeUUPS({
            proxyTarget: _getPufferProtocol(),
            implementation: address(protocolImplementation),
            data: "",
            contractName: "PufferProtocolImplementation"
        });
    }
}
