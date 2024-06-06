// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { BaseScript } from "script/BaseScript.s.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { stdJson } from "forge-std/StdJson.sol";

/**
 * @title Deposit ETH script
 * @author Puffer Finance
 * @notice Calls the `depositETH` function on PufferPool
 * @dev Example on how to run the script
 *      forge script script/SetGuardianEnclaveMeasurements.s.sol:SetEnclaveMeasurements --rpc-url=$RPC_URL --broadcast --sig "run(bytes32,bytes32)" -vvvv 0x${MR_ENCLAVE} 0x${MR_SIGNER}
 */
contract SetEnclaveMeasurements is BaseScript {
    function run(bytes32 mrenclave, bytes32 mrsigner) external broadcast {
        string memory guardiansDeployment = vm.readFile("./output/puffer.json");

        address payable module = payable(stdJson.readAddress(guardiansDeployment, ".guardianModule"));

        GuardianModule(module).setGuardianEnclaveMeasurements({ newMrEnclave: mrenclave, newMrSigner: mrsigner });
    }
}
