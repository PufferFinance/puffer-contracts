// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

struct EpochsValidatedSignature {
    bytes32 functionSelector;
    uint256 totalEpochsValidated;
    address nodeOperator;
    uint256 deadline;
    bytes[] signatures;
}
