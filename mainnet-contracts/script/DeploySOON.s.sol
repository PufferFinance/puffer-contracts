// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { SOON } from "../src/SOON.sol";

/**
 * forge script script/DeploySOON.s.sol:DeploySOON --rpc-url=$RPC_URL --private-key $PK
 *
 * deploy along with verification:
 * forge script script/DeploySOON.s.sol:DeploySOON -vvvv --rpc-url=$RPC_URL --account puffer --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast
 */
contract DeploySOON is DeployerHelper {
    function run() public {
        vm.startBroadcast();
        address multiSig = 0xE06A1ad7346Dfda7Ce9BCFba751DABFd754BAfAD;

        SOON soon = new SOON(multiSig);

        vm.label(address(soon), "SOON");

        vm.stopBroadcast();
    }
}
