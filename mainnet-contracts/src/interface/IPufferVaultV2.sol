// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferVault } from "./IPufferVault.sol";

/**
 * @title IPufferVaultV2
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufferVaultV2 is IPufferVault {
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
     * Emitted when the Vault transfers ETH to a specified address
     * @dev Signature: 0xba7bb5aa419c34d8776b86cc0e9d41e72d74a893a511f361a11af6c05e920c3d
     */
    event TransferredETH(address indexed to, uint256 amount);

    /**
     * Emitted when the Vault transfers ETH to a specified address
     * @dev Signature: 0xb10a745484e9798f0014ea028d76169706f92e7eea5d5bb66001c1400769785d
     */
    event ExitFeeBasisPointsSet(uint256 previousFee, uint256 newFee);

    /**
     * Emitted when the Vault gets ETH from Lido
     * @dev Signature: 0xb5cd6ba4df0e50a9991fc91db91ea56e2f134e498a70fc7224ad61d123e5bbb0
     */
    event LidoWithdrawal(uint256 expectedWithdrawal, uint256 actualWithdrawal);

    /**
     * @notice Returns the current exit fee basis points
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
}
