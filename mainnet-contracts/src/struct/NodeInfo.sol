// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @dev Everything is packed in 1 storage slot
 */
struct NodeInfo {
    uint64 activeValidatorCount; // Number of active validators
    uint64 pendingValidatorCount; // Number of pending validators (registered but not yet provisioned)
    uint96 vtBalance; // Validator ticket balance
    uint8 numBatches; // Number of batches
        // @todo: Adapt with VT rework to fit a single slot
}
