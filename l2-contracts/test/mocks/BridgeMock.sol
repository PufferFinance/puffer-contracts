// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { L2RewardManager } from "../../src/L2RewardManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

contract BridgeMock is AccessManaged {
    struct TransferRequest {
        uint32 destination;
        address to;
        address asset;
        address delegate;
        uint256 amount;
        bytes callData;
    }

    TransferRequest[] public transferQueue;

    bool public instantTransfer;

    uint256 public queueIdx = 0;

    constructor(address authority) AccessManaged(authority) {
        instantTransfer = true;
    }

    function xcall(
        uint32 destination,
        address to,
        address asset,
        address delegate,
        uint256 amount,
        uint256, // slippage
        bytes calldata callData
    ) external payable restricted returns (bytes memory) {
        // 1 == mainnet, 2 == l2
        uint32 originId = destination == 1 ? 2 : 1;

        if (instantTransfer) {
            // In our case, we don't need to do any Minting or Burning of tokens
            // We just transfer the tokens from L1RewardManager to L2RewardManager
            if (amount != 0) {
                IERC20(asset).transferFrom(msg.sender, to, amount);
            }

            L2RewardManager(to).xReceive(
                keccak256(abi.encodePacked(to, amount, asset, delegate, callData)), // transferId
                amount,
                asset,
                msg.sender,
                originId,
                callData
            );
        } else {
            // Move the tokens here
            if (amount != 0) {
                IERC20(asset).transferFrom(msg.sender, to, amount);
            }

            // Queue the transfer request
            transferQueue.push(
                TransferRequest({
                    destination: destination,
                    to: to,
                    asset: asset,
                    delegate: delegate,
                    amount: amount,
                    callData: callData
                })
            );
        }

        return "";
    }

    function finalizeBridging() external restricted {
        require(queueIdx < transferQueue.length, "No transfers to finalize");

        // Get the first transfer request
        TransferRequest memory request = transferQueue[queueIdx];

        // Execute the transfer
        if (request.amount != 0) {
            IERC20(request.asset).transferFrom(address(this), request.to, request.amount);
        }

        L2RewardManager(request.to).xReceive(
            keccak256(abi.encodePacked(request.to, request.amount, request.asset, request.delegate, request.callData)), // transferId
            request.amount,
            request.asset,
            msg.sender,
            request.destination,
            request.callData
        );

        delete transferQueue[queueIdx];

        // Advance the queue start pointer
        queueIdx++;
    }
}
