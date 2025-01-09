// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferVaultV2 } from "./IPufferVaultV2.sol";

/**
 * @title IPufferVaultV3
 * @notice Interface for the PufferVault version 3 contract.
 * @custom:security-contact security@puffer.fi
 */
interface IPufferVaultV3 is IPufferVaultV2 {
    /**
     * @dev Thrown if the caller is not a valid grant recipient.
     */
    error NotGrantRecipient();

    /**
     * @dev Thrown if the requested grant amount exceeds the maximum allowed.
     */
    error ExceedsMaxGrantAmount();

    /**
     * @dev Thrown if the Vault does not have enough ETH liquidity to transfer the grant.
     */
    error InsufficientETHBalance();

    /**
     * @dev Thrown if the Vault does not have enough WETH liquidity to transfer the grant.
     */
    error InsufficientWETHBalance();

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
     * @notice Returns the total reward mint amount.
     * @return The total minted rewards amount.
     */
    function getTotalRewardMintAmount() external view returns (uint256);

    /**
     * @notice Returns the total reward mint amount.
     * @return The total deposited rewards amount.
     */
    function getTotalRewardDepositAmount() external view returns (uint256);

    /**
     * @notice Emitted when the rewards are deposited to the PufferVault
     * @dev Signature "0x3a278b4e83c8793751d35f41b90435c742acf0dfdd54a8cbe09aa59720db93a5"
     */
    event UpdatedTotalRewardsAmount(
        uint256 previousTotalRewardsAmount, uint256 newTotalRewardsAmount, uint256 depositedETHAmount
    );

    /**
     * @notice Emitted when the grant recipient status of an account is updated.
     * @param account The address of the account whose grant recipient status was updated.
     * @param isRecipient A boolean indicating the updated grant recipient status.
     */
    event GrantRecipientUpdated(address indexed account, bool isRecipient);

    /**
     * @notice Emitted when the maximum grant amount is updated.
     * @param maxGrantAmount The new maximum grant amount.
     */
    event MaxGrantAmountUpdated(uint256 maxGrantAmount);

    /**
     * @notice Emitted when a grant is claimed by a recipient.
     * @param recipient The address of the grant recipient who claimed the grant.
     * @param amount The amount of the grant that was claimed.
     */
    event GrantClaimed(address indexed recipient, uint256 amount);
}
