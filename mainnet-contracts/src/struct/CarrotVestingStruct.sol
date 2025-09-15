// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @notice Struct to store the vesting information for a user
 * @param depositedAmount The amount of CARROT that was deposited
 * @param claimedAmount The amount of PUFFER that has been claimed so far
 * @param lastClaimedTimestamp The timestamp when the user last claimed
 * @param depositedTimestamp The timestamp when the user deposited
 */
struct Vesting {
    uint128 depositedAmount;
    uint128 claimedAmount;
    uint48 lastClaimedTimestamp;
    uint48 depositedTimestamp;
}
