// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/**
 * @title RewardsCoordinator
 * @author Eigen Labs Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice  This is the contract for rewards in EigenLayer. The main functionalities of this contract are
 * - enabling any ERC20 rewards from AVSs to their operators and stakers for a given time range
 * - allowing stakers and operators to claim their earnings including a commission bips for operators
 * - allowing the protocol to provide ERC20 tokens to stakers over a specified time range
 */
interface IRewardsCoordinator {
    /**
     * @notice Sets the address of the entity that can call `processClaim` on behalf of the earner (msg.sender)
     * @param claimer The address of the entity that can call `processClaim` on behalf of the earner
     * @dev Only callable by the `earner`
     */
    function setClaimerFor(address claimer) external;
}
