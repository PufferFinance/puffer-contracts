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
     * @notice Thrown when attempting to set a max withdrawal amount below the minimum withdrawal amount
     */
    error InvalidMaxWithdrawalAmount();

    /**
     * @notice Thrown when attempting to request a withdrawal to the zero address
     */
    error WithdrawalToZeroAddress();

    /**
     * @notice Thrown when attempting to request multiple withdrawals in the same transaction
     */
    error MultipleWithdrawalsAreForbidden();

    /**
     * @notice Thrown when attempting to change the batch size
     */
    error BatchSizeCannotChange();

    /**
     * @notice Thrown when attempting to finalize a batch that has already been finalized
     */
    error BatchAlreadyFinalized(uint256 batchIndex);

    /**
     * @notice Thrown when attempting to complete a withdrawal that hasn't been finalized yet
     */
    error NotFinalized();

    /**
     * @notice Thrown when attempting to return excess ETH to the vault but not all withdrawals from that batch have been claimed
     */
    error NotAllWithdrawalsClaimed();

    /**
     * @notice Thrown when attempting to return excess ETH to the vault but the batch has already been returned
     */
    error AlreadyReturned();

    /**
     * @notice Thrown when attempting to complete a withdrawal that has already been completed
     */
    error WithdrawalAlreadyCompleted();

    /**
     * @notice Thrown when attempting to finalize batches that aren't full
     */
    error BatchesAreNotFull();

    /**
     * @notice Thrown when attempting to withdraw an amount below the minimum threshold
     */
    error WithdrawalAmountTooLow();

    /**
     * @notice Thrown when attempting to withdraw an amount above the maximum threshold
     */
    error WithdrawalAmountTooHigh();

    /**
     * @notice Emitted when a withdrawal is requested
     * @param withdrawalIdx The index of the requested withdrawal
     * @param batchIdx The index of the batch the withdrawal is added to
     * @param pufETHAmount The amount of pufETH requested for withdrawal
     * @param recipient The address that will receive the withdrawn ETH
     */
    event WithdrawalRequested(
        uint256 indexed withdrawalIdx, uint256 indexed batchIdx, uint256 pufETHAmount, address indexed recipient
    );

    /**
     * @notice Emitted when a withdrawal batch is finalized
     * @param batchIdx The index of the finalized batch
     * @param expectedETHAmount The expected amount of ETH to be withdrawn
     * @param actualEthAmount The actual amount of ETH withdrawn
     * @param pufETHBurnAmount The amount of pufETH burned in the process
     */
    event BatchFinalized(
        uint256 indexed batchIdx, uint256 expectedETHAmount, uint256 actualEthAmount, uint256 pufETHBurnAmount
    );

    /**
     * @notice Emitted when the max withdrawal amount is changed
     * @param oldMaxWithdrawalAmount The old max withdrawal amount
     * @param newMaxWithdrawalAmount The new max withdrawal amount
     */
    event MaxWithdrawalAmountChanged(uint256 oldMaxWithdrawalAmount, uint256 newMaxWithdrawalAmount);

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
     * @notice Emitted when excess ETH is returned to the vault
     * @param batchIndices The indices of the batches from which excess ETH was returned
     * @param totalExcessETH The total amount of excess ETH returned to the vault
     */
    event ExcessETHReturned(uint256[] batchIndices, uint256 totalExcessETH);

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
     * Only one withdrawal can be requested per transaction
     * @param pufETHAmount Amount of pufETH to withdraw
     * @param recipient Address to receive the withdrawn ETH
     */
    function requestWithdrawal(uint128 pufETHAmount, address recipient) external;

    /**
     * @notice Request withdrawals using permit
     * Only one withdrawal can be requested per transaction
     * @dev This function will work if the `msg.sender` has approved this contract to spend the pufETH amount
     * @param permitData The permit data for the withdrawal
     * @param recipient The address to receive the withdrawn ETH
     */
    function requestWithdrawalWithPermit(Permit calldata permitData, address recipient) external;

    /**
     * @notice Complete a queued withdrawal
     * @param withdrawalIdx The index of the withdrawal to complete
     */
    function completeQueuedWithdrawal(uint256 withdrawalIdx) external;

    /**
     * @notice Returns the excess ETH transferred from the Vault to the WithdrawalManager
     * This can happen if there is a discrepancy between the expected ETH amount and the actual ETH amount withdrawn because of the pufETH:ETH exchange rate.
     * @param batchIndices The indices of the batches to return the dust from
     */
    function returnExcessETHToVault(uint256[] calldata batchIndices) external;

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

    /**
     * @notice Returns the max withdrawal amount
     * @return The max withdrawal amount
     */
    function getMaxWithdrawalAmount() external view returns (uint256);

    /**
     * @notice Returns the length of the withdrawals
     * @return The length of the withdrawals
     */
    function getWithdrawalsLength() external view returns (uint256);

    /**
     * @notice Returns the batch details for a given batch index
     * @param batchIdx The index of the batch to retrieve
     * @return The WithdrawalBatch struct containing the details of the batch
     */
    function getBatch(uint256 batchIdx) external view returns (PufferWithdrawalManagerStorage.WithdrawalBatch memory);
}
