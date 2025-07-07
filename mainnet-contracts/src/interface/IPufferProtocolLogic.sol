// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;


interface IPufferProtocolLogic {
    function _requestConsolidation(bytes32 moduleName, uint256[] calldata srcIndices, uint256[] calldata targetIndices) external payable;
}