// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPermissionedOracle
 * @notice Oracle for tracking ETH locked by permissioned validators
 * @dev Unlike PufferOracleV2 which uses (count * 32 ETH), this tracks actual amounts
 *      to support Pectra variable stake (32-2048 ETH) for non-restaked validators
 * @custom:security-contact security@puffer.fi
 */
interface IPermissionedOracle {
    /**
     * @notice Emitted when a permissioned validator is provisioned
     * @param moduleName The module name
     * @param amount The staked ETH amount
     */
    event PermissionedValidatorProvisioned(bytes32 indexed moduleName, uint256 amount);

    /**
     * @notice Emitted when a permissioned validator exits
     * @param moduleName The module name
     * @param amount The exited ETH amount
     */
    event PermissionedValidatorExited(bytes32 indexed moduleName, uint256 amount);

    /**
     * @notice Emitted when locked ETH is adjusted due to slashing/inactivity
     * @param moduleName The module name
     * @param reductionAmount The amount reduced
     */
    event LockedEthAdjusted(bytes32 indexed moduleName, uint256 reductionAmount);

    /**
     * @notice Thrown when trying to exit more ETH than locked
     * @param moduleName The module name
     * @param lockedAmount The current locked amount
     * @param requestedAmount The requested exit amount
     */
    error InsufficientLockedEth(bytes32 moduleName, uint256 lockedAmount, uint256 requestedAmount);

    /**
     * @notice Returns total locked ETH across all permissioned validators
     * @return The total locked ETH amount
     */
    function getLockedEthAmount() external view returns (uint256);

    /**
     * @notice Returns locked ETH for a specific module
     * @param moduleName The module name
     * @return The locked ETH amount for the module
     */
    function getModuleLockedEth(bytes32 moduleName) external view returns (uint256);

    /**
     * @notice Called when a permissioned validator is provisioned
     * @param moduleName The module name
     * @param amount The staked ETH amount (32-2048 ETH)
     */
    function provisionValidator(bytes32 moduleName, uint256 amount) external;

    /**
     * @notice Called when a permissioned validator exits
     * @param moduleName The module name
     * @param amount The exited ETH amount
     */
    function exitValidator(bytes32 moduleName, uint256 amount) external;

    /**
     * @notice Adjusts locked ETH amount due to slashing or inactivity penalties
     * @param moduleName The module name
     * @param reductionAmount The amount to reduce from locked ETH
     * @dev This should be called when validator balance decreases due to slashing
     */
    function adjustLockedEth(bytes32 moduleName, uint256 reductionAmount) external;
}
