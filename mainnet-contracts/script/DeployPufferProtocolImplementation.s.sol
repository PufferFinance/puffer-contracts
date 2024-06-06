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

/**
 * forge script script/DeployPufferProtocolImplementation.s.sol:DeployPufferProtocolImplementation --rpc-url=$RPC_URL --private-key $PK
 */
contract DeployPufferProtocolImplementation is Script {
    function run() public {
        require(block.chainid == 17000, "This script is only for Puffer Holesky testnet");

        vm.startBroadcast();
        new PufferProtocol({
            pufferVault: PufferVaultV2(payable(0x98408eadD0C7cC9AebbFB2AD2787c7473Db7A1fa)),
            validatorTicket: ValidatorTicket(address(0xA143c6bFAff0B25B485454a9a8DB94dC469F8c3b)),
            guardianModule: GuardianModule(payable(0xD349FdCD0e4451381bfE7cba3ac28773E176b326)),
            moduleManager: address(0xe4695ab93163F91665Ce5b96527408336f070a71),
            oracle: IPufferOracleV2(0xEf93AA29F627465A7f58A1F25980c90116f27b74),
            beaconDepositContract: 0x4242424242424242424242424242424242424242
        });
    }
}
