// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { PufferVaultV5 } from "../src/PufferVaultV5.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { ValidatorTicket } from "../src/ValidatorTicket.sol";
import { IPufferOracleV2 } from "../src/interface/IPufferOracleV2.sol";
import { IPermissionedOracle } from "../src/interface/IPermissionedOracle.sol";

/**
 * @title UpgradePufferProtocol
 * @author Puffer Finance
 * @notice Upgrades the PufferProtocol implementation to add permissioned validator support.
 * @dev PufferProtocol uses immutables, so a new implementation must be deployed with
 *      the PermissionedOracle address set. Deploy PermissionedOracle first via
 *      DeployPermissionedOracle.s.sol, then run this script with the oracle address.
 *
 *      On Holesky the upgrade is executed immediately. On mainnet the calldata is logged
 *      for queueing through the Timelock.
 *
 *      forge script script/UpgradePufferProtocol.s.sol:UpgradePufferProtocol \
 *          --sig 'run(address)' <PERMISSIONED_ORACLE_ADDRESS> \
 *          -vvvv --rpc-url=$RPC_URL --broadcast --verify
 */
contract UpgradePufferProtocol is DeployerHelper {
    function run(address permissionedOracle) public {
        vm.startBroadcast();

        PufferProtocol existingProxy = PufferProtocol(payable(_getPufferProtocol()));

        PufferProtocol newImplementation = new PufferProtocol({
            pufferVault: PufferVaultV5(payable(existingProxy.PUFFER_VAULT())),
            guardianModule: existingProxy.GUARDIAN_MODULE(),
            moduleManager: address(existingProxy.PUFFER_MODULE_MANAGER()),
            validatorTicket: existingProxy.VALIDATOR_TICKET(),
            oracle: existingProxy.PUFFER_ORACLE(),
            beaconDepositContract: address(existingProxy.BEACON_DEPOSIT_CONTRACT()),
            permissionedOracle: IPermissionedOracle(permissionedOracle)
        });

        _consoleLogOrUpgradeUUPS({
            proxyTarget: _getPufferProtocol(),
            implementation: address(newImplementation),
            data: "",
            contractName: "PufferProtocolImplementation"
        });

        vm.stopBroadcast();
    }
}
