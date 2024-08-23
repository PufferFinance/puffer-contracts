// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title WithdrawalManager
 * @dev Manages the withdrawal process for the Puffer protocol
 */
contract WithdrawalManager {
    error BatchAlreadyFinalized();
    error NotFinalized();
    error BatchNotFull();
    error WithdrawalAmountTooLow();

    event WithdrawalRequested(uint256 indexed batchIndex, uint256 pufETHAmount, address indexed recipient);
    event BatchFinalized(
        uint256 indexed batchIndex, uint256 expectedETHAmount, uint256 actualEthAmount, uint256 pufETHBurnAmount
    );
    event WithdrawalCompleted(
        uint256 indexed withdrawalIdx, uint256 ethPayoutAmount, uint256 payoutExchangeRate, address indexed recipient
    );

    PufferVaultV3 public immutable PUFFER_VAULT;
    uint8 public constant BATCH_SIZE = 10;
    uint256 public constant MIN_WITHDRAWAL_AMOUNT = 0.01 ether;

    struct Withdrawal {
        uint128 pufETHAmount;
        uint128 pufETHToEthExchangeRate;
        address recipient;
    }

    struct WithdrawalBatch {
        uint128 toBurn;
        uint128 toTransfer;
        uint256 pufETHToEthExchangeRate;
    }

    Withdrawal[] public withdrawals;
    WithdrawalBatch[] public withdrawalBatches;
    uint256 public finalizedWithdrawalBatch;

    /**
     * @dev Constructor to initialize the WithdrawalManager
     * @param pufferVault Address of the PufferVaultV3 contract
     */
    constructor(PufferVaultV3 pufferVault) {
        PUFFER_VAULT = pufferVault;
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable { }

    /**
     * @dev Request a withdrawal of pufETH
     * @param pufETHAmount Amount of pufETH to withdraw
     * @param recipient Address to receive the withdrawn ETH
     */
    function requestWithdrawals(uint256 pufETHAmount, address recipient) external {
        if (pufETHAmount < MIN_WITHDRAWAL_AMOUNT) {
            revert WithdrawalAmountTooLow();
        }

        uint256 batchIndex = withdrawals.length / BATCH_SIZE;

        if (batchIndex == withdrawalBatches.length) {
            // Push empty batch
            withdrawalBatches.push(WithdrawalBatch({ toBurn: 0, toTransfer: 0, pufETHToEthExchangeRate: 0 }));
        }

        PUFFER_VAULT.transferFrom(msg.sender, address(this), pufETHAmount);

        uint256 exchangeRate = PUFFER_VAULT.convertToAssets(1 ether);
        uint256 expectedETHAmount = pufETHAmount * exchangeRate / 1 ether;

        WithdrawalBatch storage batch = withdrawalBatches[batchIndex];
        batch.toBurn += uint128(pufETHAmount);
        batch.toTransfer += uint128(expectedETHAmount);

        // Update the withdrawal
        withdrawals.push(
            Withdrawal({
                pufETHAmount: uint128(pufETHAmount),
                pufETHToEthExchangeRate: uint128(exchangeRate),
                recipient: recipient
            })
        );

        emit WithdrawalRequested(batchIndex, pufETHAmount, recipient);
    }

    /**
     * @dev Finalize withdrawals for a batch or multiple batches
     * @param withdrawalBatchIndex The index of the last batch to finalize
     */
    function finalizeWithdrawals(uint256 withdrawalBatchIndex) external {
        if (withdrawalBatchIndex <= finalizedWithdrawalBatch && withdrawalBatchIndex != 0) {
            revert BatchAlreadyFinalized();
        }

        for (uint256 i = finalizedWithdrawalBatch; i <= withdrawalBatchIndex;) {
            if (withdrawals.length < (i + 1) * BATCH_SIZE) {
                revert BatchNotFull();
            }

            //@audit how can this be manipulated?
            uint256 batchFinalizationExchangeRate = PUFFER_VAULT.convertToAssets(1 ether);

            WithdrawalBatch storage batch = withdrawalBatches[i];
            uint256 expectedETHAmount = batch.toTransfer;
            uint256 pufETHBurnAmount = batch.toBurn;

            uint256 ethAmount = (pufETHBurnAmount * batchFinalizationExchangeRate) / 1 ether;
            uint256 transferAmount = Math.min(expectedETHAmount, ethAmount);

            PUFFER_VAULT.transferETH(address(this), transferAmount);
            PUFFER_VAULT.burn(pufETHBurnAmount);

            batch.pufETHToEthExchangeRate = batchFinalizationExchangeRate;

            emit BatchFinalized(i, expectedETHAmount, transferAmount, pufETHBurnAmount);

            unchecked {
                ++i;
            }
        }
        finalizedWithdrawalBatch = withdrawalBatchIndex;
    }

    /**
     * @dev Complete a queued withdrawal
     * @param withdrawalIdx The index of the withdrawal to complete
     */
    function completeQueuedWithdrawal(uint256 withdrawalIdx) external {
        if (withdrawalIdx < finalizedWithdrawalBatch * BATCH_SIZE) {
            revert NotFinalized();
        }

        Withdrawal memory withdrawal = withdrawals[withdrawalIdx];
        uint256 batchSettlementExchangeRate = withdrawalBatches[withdrawalIdx / BATCH_SIZE].pufETHToEthExchangeRate;

        uint256 payoutExchangeRate = Math.min(withdrawal.pufETHToEthExchangeRate, batchSettlementExchangeRate);
        uint256 payoutAmount = (uint256(withdrawal.pufETHAmount) * payoutExchangeRate) / 1 ether;

        // remove data for some gas savings
        delete withdrawals[withdrawalIdx];

        emit WithdrawalCompleted(withdrawalIdx, payoutAmount, payoutExchangeRate, withdrawal.recipient);

        Address.sendValue(payable(withdrawal.recipient), payoutAmount);
    }
}
