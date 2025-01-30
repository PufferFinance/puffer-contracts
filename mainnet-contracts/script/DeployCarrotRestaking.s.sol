// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { CarrotRestaking } from "../src/CarrotRestaking.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";

/**
 * forge script script/DeployCarrotRestaking.s.sol:DeployCarrotRestaking --rpc-url=$RPC_URL --private-key $PK
 *
 * deploy along with verification:
 * forge script script/DeployCarrotRestaking.s.sol:DeployCarrotRestaking -vvvv --rpc-url=$RPC_URL --account puffer --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast
 */
contract DeployCarrotRestaking is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        address carrot = _getCARROT();
        // TODO: get admin address // 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0 is dev wallet on holesky for testing
        address admin = 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;

        CarrotRestaking restaking = new CarrotRestaking(address(carrot), admin);

        vm.label(address(restaking), "CarrotRestaking");

        vm.stopBroadcast();
    }
}
