// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ILidoWithdrawalQueue } from "../../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract LidoWithdrawalQueueMock is ILidoWithdrawalQueue, ERC721 {
    constructor() ERC721("LidoWithdrawalQueueMock", "LIDO") { }

    function requestWithdrawals(uint256[] calldata, address) external returns (uint256[] memory) {
        _mint(msg.sender, 1);
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 1;
        return requestIds;
    }

    function claimWithdrawal(uint256 _requestId) external { }
}
