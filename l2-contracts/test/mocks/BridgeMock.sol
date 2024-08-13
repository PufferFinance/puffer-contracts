// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { L2RewardManager } from "../../src/L2RewardManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
        IERC20(asset).transferFrom(msg.sender, to, amount);

        L2RewardManager(to).xReceive(
            keccak256(abi.encodePacked(to, amount, asset, delegate, callData)), // transferId
            amount,
            asset,
            msg.sender,
            destination,
            callData
        );

        return "";
    }
}