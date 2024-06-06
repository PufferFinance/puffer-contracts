// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";

/**
 * @title Deposit ETH script
 * @author Puffer Finance
 * @notice Calls the `depositETH` function on PufferPool
 * @dev Example on how to run the script
 *      forge script script/DeployNewPufferModule.s.sol:DeployNewPufferModule --rpc-url=$RPC_URL --broadcast --sig "run(string)" "SOME_MODULE_NAME" -vvvv --private-key $PK
 */
contract DeployNewPufferModule is BaseScript {
    function run(string memory moduleName) external broadcast {
        string memory pufferDeployment = vm.readFile("./output/puffer.json");
        address payable protocol = payable(stdJson.readAddress(pufferDeployment, ".protocol"));

        PufferProtocol(protocol).createPufferModule(bytes32(abi.encodePacked(moduleName)));
    }
}
