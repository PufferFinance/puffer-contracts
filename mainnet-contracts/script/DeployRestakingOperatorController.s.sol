// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { RestakingOperatorController } from "../src/RestakingOperatorController.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";

/**
 * forge script script/DeployRestakingOperatorController.s.sol:DeployRestakingOperatorController --rpc-url=$RPC_URL --private-key $PK
 *
 * deploy along with verification:
 * forge script script/DeployRestakingOperatorController.s.sol:DeployRestakingOperatorController -vvvv --rpc-url=$HOLESKY_RPC_URL --account puffer --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast
 */
contract DeployRestakingOperatorController is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        RestakingOperatorController restakingOperatorController = new RestakingOperatorController(
            _getAccessManager(),
            _getAVSContractsRegistry()
        );

        vm.label(address(restakingOperatorController), "RestakingOperatorController");

    }
}
