// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV3 } from "../PufferVaultV3.sol";
import { Permit } from "../structs/Permit.sol";
import { PufferWithdrawalManagerStorage } from "../PufferWithdrawalManagerStorage.sol";

/**
 * @title IPufferWithdrawalManager
 * @author Puffer Finance
 * @notice Interface for the PufferWithdrawalManager contract
 * @custom:security-contact security@puffer.fi
 */
interface IPufferWithdrawalManager {
    /**
     * @notice Thrown when attempting to finalize a batch that has already been finalized
     */
    error BatchAlreadyFinalized();

    /**
     * @notice Thrown when attempting to complete a withdrawal that hasn't been finalized yet
     */
    error NotFinalized();

    /**
     * @notice Thrown when attempting to complete a withdrawal that doesn't exist
     */
    error InvalidWithdrawalIndex();

    /**
     * @notice Thrown when attempting to complete a withdrawal that has already been completed
     */
    error WithdrawalAlreadyCompleted();

    /**
     * @notice Thrown when attempting to finalize a batch that isn't full yet
     */
    error BatchNotFull();

    /**
     * @notice Thrown when attempting to withdraw an amount below the minimum threshold
     */
    error WithdrawalAmountTooLow();

    /**
     * @notice Emitted when a withdrawal is requested
     * @param withdrawalIdx The index of the requested withdrawal
     * @param batchIndex The index of the batch the withdrawal is added to
     * @param pufETHAmount The amount of pufETH requested for withdrawal
     * @param recipient The address that will receive the withdrawn ETH
     */
    event WithdrawalRequested(
        uint256 indexed withdrawalIdx, uint256 indexed batchIndex, uint256 pufETHAmount, address indexed recipient
    );

    /**
     * @notice Emitted when a withdrawal batch is finalized
     * @param batchIndex The index of the finalized batch
     * @param expectedETHAmount The expected amount of ETH to be withdrawn
     * @param actualEthAmount The actual amount of ETH withdrawn
     * @param pufETHBurnAmount The amount of pufETH burned in the process
     */
    event BatchFinalized(
        uint256 indexed batchIndex, uint256 expectedETHAmount, uint256 actualEthAmount, uint256 pufETHBurnAmount
    );

    /**
     * @notice Emitted when a withdrawal is completed
     * @param withdrawalIdx The index of the completed withdrawal
     * @param ethPayoutAmount The amount of ETH paid out
     * @param payoutExchangeRate The exchange rate used for the payout
     * @param recipient The address that received the withdrawn ETH
     */
    event WithdrawalCompleted(
        uint256 indexed withdrawalIdx, uint256 ethPayoutAmount, uint256 payoutExchangeRate, address indexed recipient
    );

    /**
     * @notice Returns the address of the PufferVaultV3 contract
     * @return The address of the PufferVaultV3 contract
     */
    function PUFFER_VAULT() external view returns (PufferVaultV3);

    /**
     * @notice Returns the minimum withdrawal amount
     * @return The minimum withdrawal amount
     */
    function MIN_WITHDRAWAL_AMOUNT() external view returns (uint256);

    /**
     * @notice Request a withdrawal of pufETH
     * @param pufETHAmount Amount of pufETH to withdraw
     * @param recipient Address to receive the withdrawn ETH
     */
    function requestWithdrawal(uint128 pufETHAmount, address recipient) external;

    /**
     * @notice Request withdrawals using permit
     * @dev This function will work if the `msg.sender` has approved this contract to spend the pufETH amount
     * @param permitData The permit data for the withdrawal
     * @param recipient The address to receive the withdrawn ETH
     */
    function requestWithdrawalsWithPermit(Permit calldata permitData, address recipient) external;

    /**
     * @notice Complete a queued withdrawal
     * @param withdrawalIdx The index of the withdrawal to complete
     */
    function completeQueuedWithdrawal(uint256 withdrawalIdx) external;

    /**
     * @notice Returns the index of the last finalized withdrawal batch
     * @return The index of the last finalized withdrawal batch
     */
    function getFinalizedWithdrawalBatch() external view returns (uint256);

    /**
     * @notice Returns the withdrawal details for a given withdrawal index
     * @param withdrawalIdx The index of the withdrawal to retrieve
     * @return The Withdrawal struct containing the details of the withdrawal
     */
    function getWithdrawal(uint256 withdrawalIdx)
        external
        view
        returns (PufferWithdrawalManagerStorage.Withdrawal memory);
}
