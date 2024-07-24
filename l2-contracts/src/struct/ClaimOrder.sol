// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 *
 * @dev A record of a single order for claim function call.
 * @param startEpoch The start epoch of the interval where the merkle root is generated from.
 * @param endEpoch The end epoch of the interval where the merkle root is generated from.
 * @param account The address of the account claiming the reward.
 * @param amount The amount of reward to claim.
 * @param merkleProof The merkle proof to verify the claim.
 */
struct ClaimOrder {
    uint256 startEpoch;
    uint256 endEpoch;
    address account;
    uint256 amount;
    bytes32[] merkleProof;
}
