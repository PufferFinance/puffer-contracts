// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPufferRevenueDepositor
 * @notice Interface for the PufferRevenueDepositor contract.
 * @custom:security-contact security@puffer.fi
 */
interface IPufferRevenueDepositor {
    /**
     * @notice Thrown when the address is invalid.
     */
    error InvalidAddress();

    /**
     * @notice Thrown when the calldata targets and data length don't match or are empty.
     */
    error InvalidDataLength();

    /**
     * @notice Thrown when the target call fails.
     */
    error TargetCallFailed();

    /**
     * @notice Thrown when the vault has undeposited rewards.
     */
    error VaultHasUndepositedRewards();

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
     * @notice Emitted when the revenue is deposited to the PufferVault
     */
    event RevenueDeposited(uint256 amount);

    /**
     * @notice Emitted when the rewards distribution window is changed
     */
    event RewardsDistributionWindowChanged(uint256 oldWindow, uint256 newWindow);

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
