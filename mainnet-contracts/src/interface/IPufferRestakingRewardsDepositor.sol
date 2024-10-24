// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPufferRestakingRewardsDepositor
 * @notice Interface for the PufferRestakingRewardsDepositor contract.
 * @custom:security-contact security@puffer.fi
 */
interface IPufferRestakingRewardsDepositor {
    /**
     * @notice Thrown when the restaking operator is already set.
     */
    error RestakingOperatorAlreadySet();

    /**
     * @notice Thrown when the restaking operator is not set.
     */
    error RestakingOperatorNotSet();

    /**
     * @notice Thrown when the vault has undeposited rewards.
     */
    error VaultHasUndepositedRewards();

    /**
     * @notice Thrown when the bps is invalid.
     */
    error InvalidBps();

    /**
     * @notice Thrown when there is nothing to distribute.
     */
    error NothingToDistribute();

    /**
     * @notice Distribution window cannot be changed if there are undeposited rewards.
     */
    error CannotChangeDistributionWindow();

    /**
     * @notice Thrown when the distribution window is invalid.
     */
    error InvalidDistributionWindow();

    /**
     * @notice Emitted when the rewards are deposited to the PufferVault
     */
    event RestakingRewardsDeposited(uint256 amount, uint256 depositRate);

    /**
     * @notice Emitted when the rewards distribution window is changed
     */
    event RewardsDistributionWindowChanged(uint256 oldWindow, uint256 newWindow);

    /**
     * @notice Emitted when a new restaking operator is added.
     * @param operator The address of the restaking operator.
     */
    event RestakingOperatorAdded(address indexed operator);

    /**
     * @notice Emitted when a restaking operator is removed.
     * @param operator The address of the restaking operator.
     */
    event RestakingOperatorRemoved(address indexed operator);

    /**
     * @notice Emitted when the RNO rewards basis points is changed.
     * @param oldBps The old RNO rewards in basis points.
     * @param newBps The new RNO rewards in basis points.
     */
    event RnoRewardsBpsChanged(uint256 oldBps, uint256 newBps);

    /**
     * @notice Emitted when the treasury rewards basis points is changed.
     * @param oldBps The old treasury rewards in basis points.
     * @param newBps The new treasury rewards in basis points.
     */
    event TreasuryRewardsBpsChanged(uint256 oldBps, uint256 newBps);

    /**
     * @notice Calculates the remaining amount of ETH that hasn't been fully accounted for in the vault's total assets.
     * @dev This is used to prevent potential sandwich attacks related to large deposits and to smooth out the restaking rewards deposits.
     */
    function getPendingDistributionAmount() external view returns (uint256);

    /**
     * @notice Get the rewards distribution window.
     * @return The rewards distribution window in seconds.
     */
    function getRewardsDistributionWindow() external view returns (uint256);
}
