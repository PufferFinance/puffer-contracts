// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPufferVaultV5
 * @notice Interface for the PufferVault version 5 contract.
 * @dev This interface combines all functionality from previous versions (V1-V4)
 * @custom:security-contact security@puffer.fi
 */
interface IPufferVaultV5 {
    /**
     * @notice Constructor parameters for bridging.
     * @param xToken The address of the xToken contract.
     * @param lockBox The address of the lockBox contract.
     * @param l2RewardManager The address of the L2 reward manager.
     */
    struct BridgingConstructorParams {
        address xToken;
        address lockBox;
        address l2RewardManager;
    }

    /**
     * @dev Thrown if the Vault doesn't have ETH liquidity to transfer to PufferModule
     */
    error ETHTransferFailed();

    /**
     * @dev Thrown if there is a deposit and a withdrawal in the same transaction
     */
    error DepositAndWithdrawalForbidden();

    /**
     * @dev Thrown if the new exit fee basis points is invalid
     */
    error InvalidExitFeeBasisPoints();

    /**
     * @dev Thrown when withdrawals are disabled and a withdrawal attempt is made
     */
    error WithdrawalsAreDisabled();

    /**
     * @dev Thrown when a withdrawal attempt is made with invalid parameters
     */
    error InvalidWithdrawal();

    /**
     * @notice Emitted when we request withdrawals from Lido
     * @dev Signature: 0x7dac5a8ab4fe1710dfba58441ca15750a9c71877b358e90aac49fc80b293e617
     */
    event RequestedWithdrawals(uint256[] requestIds);

    /**
     * @notice Emitted when we claim the withdrawals from Lido
     * @dev Signature: 0xfe1f3a60946e634f858dc1f2f911c04cba9dc419a19abcb1bb1ce905ed79e325
     */
    event ClaimedWithdrawals(uint256[] requestIds);

    /**
     * @notice Emitted when the Vault transfers ETH to a specified address
     * @dev Signature: 0xba7bb5aa419c34d8776b86cc0e9d41e72d74a893a511f361a11af6c05e920c3d
     */
    event TransferredETH(address indexed to, uint256 amount);

    /**
     * @notice Emitted when the Vault transfers ETH to a specified address
     * @dev Signature: 0xb10a745484e9798f0014ea028d76169706f92e7eea5d5bb66001c1400769785d
     */
    event ExitFeeBasisPointsSet(uint256 previousFee, uint256 newFee);

    /**
     * @notice Emitted when the Vault gets ETH from Lido
     * @dev Signature: 0xb5cd6ba4df0e50a9991fc91db91ea56e2f134e498a70fc7224ad61d123e5bbb0
     */
    event LidoWithdrawal(uint256 expectedWithdrawal, uint256 actualWithdrawal);

    /**
     * @notice Emitted when the rewards are deposited to the PufferVault
     * @dev Signature: 0x3a278b4e83c8793751d35f41b90435c742acf0dfdd54a8cbe09aa59720db93a5
     */
    event UpdatedTotalRewardsAmount(
        uint256 previousTotalRewardsAmount, uint256 newTotalRewardsAmount, uint256 depositedETHAmount
    );

    /**
     * @notice Returns the current exit fee basis points
     * @return The current exit fee in basis points
     */
    function getExitFeeBasisPoints() external view returns (uint256);

    /**
     * @notice Deposits native ETH into the Puffer Vault
     * @param receiver The recipient of pufETH tokens
     * @return shares The amount of pufETH received from the deposit
     */
    function depositETH(address receiver) external payable returns (uint256);

    /**
     * @notice Deposits stETH into the Puffer Vault
     * @param stETHSharesAmount The shares amount of stETH to deposit
     * @param receiver The recipient of pufETH tokens
     * @return shares The amount of pufETH received from the deposit
     */
    function depositStETH(uint256 stETHSharesAmount, address receiver) external returns (uint256);

    /**
     * @notice Returns the total reward mint amount.
     * @return The total minted rewards amount.
     */
    function getTotalRewardMintAmount() external view returns (uint256);

    /**
     * @notice Returns the total reward deposit amount.
     * @return The total deposited rewards amount.
     */
    function getTotalRewardDepositAmount() external view returns (uint256);
}
