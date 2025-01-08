// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { CARROT } from "../src/CARROT.sol";

/**
 * forge script script/DeployCARROT.s.sol:DeployCARROT --rpc-url=$RPC_URL --private-key $PK
 *
 * deploy along with verification:
 * forge script script/DeployCARROT.s.sol:DeployCARROT -vvvv --rpc-url=$RPC_URL --account puffer --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast
 */
contract DeployCARROT is DeployerHelper {
    function run() public {
        vm.startBroadcast();
        address multiSig = 0xE06A1ad7346Dfda7Ce9BCFba751DABFd754BAfAD;

        CARROT carrot = new CARROT(multiSig);

        vm.label(address(carrot), "CARROT");

        vm.stopBroadcast();
    }
}
