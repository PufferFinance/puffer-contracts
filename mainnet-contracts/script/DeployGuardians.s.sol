// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { BaseScript } from "script/BaseScript.s.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { GuardiansDeployment } from "./DeploymentStructs.sol";
import { ISessionRegistry } from "@automata-network/automata-tee-workload-measurement/interfaces/registries/ISessionRegistry.sol";

// forge script script/1_DeployGuardians.s.sol:DeployGuardians --rpc-url=$EPHEMERY_RPC_URL --sig 'run(address, address, address[] calldata, uint256)' <sessionRegistry> <accessManager> "[0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0]" 1
contract DeployGuardians is BaseScript {
    function run(
        ISessionRegistry sessionRegistry,
        AccessManager accessManager,
        address[] calldata guardians,
        uint256 threshold
    ) public broadcast returns (GuardiansDeployment memory) {
        vm.label(address(accessManager), "AccessManager");

        GuardianModule module = new GuardianModule(sessionRegistry, guardians, threshold, address(accessManager));

        GuardiansDeployment memory deployment;
        deployment.accessManager = address(accessManager);
        deployment.guardianModule = address(module);
        deployment.sessionRegistry = address(sessionRegistry);

        return deployment;
    }
}
