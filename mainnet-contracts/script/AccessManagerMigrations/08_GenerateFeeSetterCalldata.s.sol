// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_DAO } from "../../script/Roles.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";

// forge script script/AccessManagerMigrations/08_GenerateFeeSetterCalldata.s.sol:GenerateFeeSetterCalldata -vvvv --sig "run(address)(bytes memory)" PUFFER_VAULT_PROXY_ADDRESS
contract GenerateFeeSetterCalldata is Script {
    function run(address pufferVault) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](1);

        bytes4[] memory daoSelectors = new bytes4[](2);
        daoSelectors[0] = PufferVaultV5.setExitFeeBasisPoints.selector;
        daoSelectors[1] = PufferVaultV5.setTreasuryExitFeeBasisPoints.selector;

        calldatas[0] =
            abi.encodeWithSelector(AccessManager.setTargetFunctionRole.selector, pufferVault, daoSelectors, ROLE_ID_DAO);

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        return encodedMulticall;
    }
}
