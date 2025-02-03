// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { CarrotStaker } from "../src/CarrotStaker.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";

/**
 * forge script script/DeployCarrotStaker.s.sol:DeployCarrotStaker --rpc-url=$RPC_URL --private-key $PK
 *
 * deploy along with verification:
 * forge script script/DeployCarrotStaker.s.sol:DeployCarrotStaker -vvvv --rpc-url=$RPC_URL --account puffer --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast
 */
contract DeployCarrotStaker is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        address carrot = _getCARROT();
        // TODO: get admin address // 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0 is dev wallet on holesky for testing
        address admin = 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;

        CarrotStaker staker = new CarrotStaker(address(carrot), admin);

        vm.label(address(staker), "CarrotStaker");

        vm.stopBroadcast();
    }
}
