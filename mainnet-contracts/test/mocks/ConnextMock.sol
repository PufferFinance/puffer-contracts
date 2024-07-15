// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IConnext } from "../../src/interface/Connext/IConnext.sol";

contract ConnextMock is IConnext {
    function xcall(
        uint32 _destination,
        address _to,
        address _asset,
        address _delegate,
        uint256 _amount,
        uint256 _slippage,
        bytes calldata _callData
    ) external payable returns (bytes32) { }

    function xcall(
        uint32 _destination,
        address _to,
        address _asset,
        address _delegate,
        uint256 _amount,
        uint256 _slippage,
        bytes calldata _callData,
        uint256 _relayerFee
    ) external returns (bytes32) { }
}
