// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { IL2RewardManager } from "l2-contracts/src/interface/IL2RewardManager.sol";

// forge script script/ClaimRewards.s.sol:ClaimRewards -vvvv --rpc-url fork_rpc_url --broadcast
contract ClaimRewards is Script {
    function run() public {
        //@todo populate manually
        bytes32 intervalId = bytes32("whatever");

        bytes32[] memory merkleProof = new bytes32[](2);
        merkleProof[0] = bytes32("proof");
        merkleProof[1] = bytes32("proof2");

        address account = address(0);
        uint256 amount = 1 ether;

        IL2RewardManager.ClaimOrder[] memory claimOrders = new IL2RewardManager.ClaimOrder[](1);

        claimOrders[0] = IL2RewardManager.ClaimOrder({
            intervalId: intervalId,
            account: account,
            isL1Contract: false,
            amount: amount,
            merkleProof: merkleProof
        });

        vm.startBroadcast();
        L2RewardManager(0xb4dBcf934558d7b647A7FB21bbcd6b8370318A5c).claimRewards(claimOrders);
        vm.stopBroadcast();
    }
}
