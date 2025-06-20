// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @dev Everything is packed in 1 storage slot
 */
struct NodeInfo {
    uint64 activeValidatorCount; // Number of active validators
    uint64 pendingValidatorCount; // Number of pending validators (registered but not yet provisioned)
    uint96 deprecated_vtBalance; // Validator ticket balance
    // @dev The node operators deposit ETH, and that ETH is used to calculate the validation time for the node
    uint256 validationTime;
    uint256 epochPrice;
    uint256 totalEpochsValidated;
    uint8 numBatches; // Number of batches
        // @todo: Adapt with VT rework to fit a single slot
}
