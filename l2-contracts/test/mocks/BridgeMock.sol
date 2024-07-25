// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { L2RewardManager } from "../../src/L2RewardManager.sol";

contract BridgeMock {
    function xcall(
        uint32 destination,
        address to,
        address asset,
        address delegate,
        uint256 amount,
        uint256,
        bytes calldata callData
    ) external payable returns (bytes memory) {
        L2RewardManager(to).xReceive(
            keccak256(abi.encodePacked(to, amount, asset, delegate, callData)), // transferId
            amount,
            asset,
            msg.sender,
            destination,
            callData
        );
    }
}
