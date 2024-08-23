// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

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
    uint256 public constant BATCH_SIZE = 10;
    uint256 public constant MIN_WITHDRAWAL_AMOUNT = 0.01 ether;

    struct Withdrawal {
        uint256 pufETHAmount;
        uint256 pufETHToEthExchangeRate;
        address recipient;
    }

    struct WithdrawalBatch {
        uint256 toBurn;
        uint256 toTransfer;
        uint256 pufETHToEthExchangeRate;
    }

    Withdrawal[] public withdrawals;
    WithdrawalBatch[] public withdrawalBatches;
    uint256 finalizedWithdrawalBatch;

    constructor(PufferVaultV3 pufferVault) {
        PUFFER_VAULT = pufferVault;
    }

    receive() external payable { }

    function requestWithdrawals(uint256 pufETHAMount, address recipient) external {
        if (pufETHAMount < MIN_WITHDRAWAL_AMOUNT) {
            revert WithdrawalAmountTooLow();
        }

        uint256 batchIndex = withdrawals.length / BATCH_SIZE;

        if (batchIndex == withdrawalBatches.length) {
            // Push empty batch
            withdrawalBatches.push(WithdrawalBatch({ toBurn: 0, toTransfer: 0, pufETHToEthExchangeRate: 0 }));
        }

        // Take the pufETH from the user
        PUFFER_VAULT.transferFrom(msg.sender, address(this), pufETHAMount);

        uint256 exchangeRate = PUFFER_VAULT.convertToAssets(1 ether);

        uint256 expectedETHAmount = pufETHAMount * exchangeRate;

        // Update the batch
        withdrawalBatches[batchIndex].toBurn += pufETHAMount;
        withdrawalBatches[batchIndex].toTransfer += expectedETHAmount;

        // Update the withdrawal
        withdrawals.push(
            Withdrawal({ pufETHAmount: pufETHAMount, pufETHToEthExchangeRate: exchangeRate, recipient: recipient })
        );

        emit WithdrawalRequested(batchIndex, pufETHAMount, recipient);
    }

    function finalizeWithdrawals(uint256 withdrawalBatchIndex) external {
        if (withdrawalBatchIndex <= finalizedWithdrawalBatch && withdrawalBatchIndex != 0) {
            revert BatchAlreadyFinalized();
        }

        for (uint256 i = finalizedWithdrawalBatch; i <= withdrawalBatchIndex; ++i) {
            if (withdrawals.length < (i + 1) * BATCH_SIZE) {
                revert BatchNotFull();
            }

            //@audit how can this be manipulated?
            uint256 batchFinalizationExchangeRate = PUFFER_VAULT.convertToAssets(1 ether);

            uint256 expectedETHAmount = withdrawalBatches[i].toTransfer;
            uint256 pufETHBurnAmount = withdrawalBatches[i].toBurn;

            uint256 ethAmount = pufETHBurnAmount * batchFinalizationExchangeRate / 1 ether;

            // Return the lower of the two
            uint256 transferAmount = Math.min(expectedETHAmount, ethAmount);

            // Transfer the ETH and burn the pufETH
            PUFFER_VAULT.transferETH(address(this), transferAmount);
            PUFFER_VAULT.burn(pufETHBurnAmount);

            // Update the exchange rate of the batch
            withdrawalBatches[i].pufETHToEthExchangeRate = batchFinalizationExchangeRate;
            finalizedWithdrawalBatch = i;

            emit BatchFinalized(i, expectedETHAmount, transferAmount, pufETHBurnAmount);
        }
    }

    function completeQueuedWithdrawal(uint256 withdrawalIdx) external {
        if (withdrawalIdx < finalizedWithdrawalBatch * BATCH_SIZE) {
            revert NotFinalized();
        }

        Withdrawal memory withdrawal = withdrawals[withdrawalIdx];

        uint256 batchSettlementExchangeRate = withdrawalBatches[withdrawalIdx / BATCH_SIZE].pufETHToEthExchangeRate;

        uint256 payoutExchangeRate = Math.min(withdrawal.pufETHToEthExchangeRate, batchSettlementExchangeRate);

        uint256 payoutAmount = withdrawal.pufETHAmount * payoutExchangeRate / 1 ether;

        emit WithdrawalCompleted(withdrawalIdx, payoutAmount, payoutExchangeRate, withdrawal.recipient);

        // remove data for some gas savings
        delete withdrawals[withdrawalIdx];

        Address.sendValue(payable(withdrawal.recipient), payoutAmount);
    }
}
