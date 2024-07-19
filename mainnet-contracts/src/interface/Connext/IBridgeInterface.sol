// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

interface IBridgeInterface {
    // ============ BRIDGE ==============

    function xcall(
        uint32 destination,
        address to,
        address asset,
        address delegate,
        uint256 amount,
        uint256 slippage,
        bytes calldata callData
    ) external payable returns (bytes32);

    function xcall(
        uint32 destination,
        address to,
        address asset,
        address delegate,
        uint256 amount,
        uint256 slippage,
        bytes calldata callData,
        uint256 relayerFee
    ) external returns (bytes32);
}
