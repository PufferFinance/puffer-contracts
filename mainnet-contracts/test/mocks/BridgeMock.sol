// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IXReceiver } from "interfaces/core/IXReceiver.sol";
import {L2RewardManager} from "../../src/l2-contracts/L2RewardManager.sol";
import "forge-std/Test.sol";

contract MockBridge  {
   function xcall(
        uint32 _destination,
        address _to,
        address _asset,
        address _delegate,
        uint256 _amount,
        uint256,
        bytes calldata _callData
    ) external payable returns (bytes32) {
        L2RewardManager(_to).xReceive(
            keccak256(abi.encodePacked(_to, uint128(_amount), _asset, _delegate, _callData)), // transferId
            uint128(_amount),
            _asset,
            msg.sender,
            _destination,
            _callData
        );
        console.log("rewardAmount: ", uint128(_amount));
        return keccak256(abi.encodePacked(uint128(_amount)));
    }
}