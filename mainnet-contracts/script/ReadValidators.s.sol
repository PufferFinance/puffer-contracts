// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { BaseScript } from "script/BaseScript.s.sol";
import { IPufferProtocol } from "../src/interface/IPufferProtocol.sol";
import { Validator } from "../src/struct/Validator.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";

/**
 * @dev Example on how to run the script
 *      forge script script/ReadValidators.s.sol:ReadValidators --rpc-url=$HOLESKY_RPC_URL --broadcast --sig "run(bytes32)" -vvvv 0x4e4f5f52455354414b494e470000000000000000000000000000000000000000
 */
contract ReadValidators is BaseScript {
    function run() external broadcast {
        // Validator[] memory validators = IPufferProtocol(0x4982C744Ef2694Af2970D3eB8a58744ed3cB1b1D).getValidators(bytes32("PUFFER_MODULE_0"));
        // for (uint256 i = 0; i < validators.length; ++i) {
        //     console.log(validators[i].node);
        // }

        for (uint256 i = 0; i < 20; ++i) {
            console.log(i);
            Validator memory validator = IPufferProtocol(0x4982C744Ef2694Af2970D3eB8a58744ed3cB1b1D).getValidatorInfo(
                bytes32("PUFFER_MODULE_0"), i
            );
            console.log(validator.node);
            console.logBytes(validator.pubKey);
        }
    }
}
