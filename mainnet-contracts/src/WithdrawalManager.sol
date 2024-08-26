// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IWithdrawalManager } from "./interface/IWithdrawalManager.sol";
import { WithdrawalManagerStorage } from "./WithdrawalManagerStorage.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title WithdrawalManager
 * @dev Manages the withdrawal process for the Puffer protocol
 */
contract WithdrawalManager is
    IWithdrawalManager,
    WithdrawalManagerStorage,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    PufferVaultV3 public immutable PUFFER_VAULT;
    uint256 public constant BATCH_SIZE = 10;
    uint256 public constant MIN_WITHDRAWAL_AMOUNT = 0.01 ether;

    /**
     * @dev Constructor to initialize the WithdrawalManager
     * @param pufferVault Address of the PufferVaultV3 contract
     */
    constructor(PufferVaultV3 pufferVault) {
        PUFFER_VAULT = pufferVault;
        _disableInitializers();
    }

    receive() external payable { }

    /**
     * @notice Initializes the contract
     */
    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
    }

    /**
     * @inheritdoc IWithdrawalManager
     */
    function requestWithdrawals(uint128 pufETHAmount, address recipient) external {
        if (pufETHAmount < MIN_WITHDRAWAL_AMOUNT) {
            revert WithdrawalAmountTooLow();
        }
        WithdrawalManagerStorageStruct storage $ = _getWithdrawalManagerStorage();
        uint256 batchIndex = $.withdrawals.length / BATCH_SIZE;

        if (batchIndex == $.withdrawalBatches.length) {
            // Push empty batch
            $.withdrawalBatches.push(WithdrawalBatch({ toBurn: 0, toTransfer: 0, pufETHToEthExchangeRate: 0 }));
        }

        PUFFER_VAULT.transferFrom(msg.sender, address(this), pufETHAmount);

        uint256 exchangeRate = PUFFER_VAULT.convertToAssets(1 ether);
        uint256 expectedETHAmount = pufETHAmount * exchangeRate / 1 ether;

        WithdrawalBatch storage batch = $.withdrawalBatches[batchIndex];
        batch.toBurn += uint96(pufETHAmount);
        batch.toTransfer += uint96(expectedETHAmount);

        // Update the withdrawal
        $.withdrawals.push(
            Withdrawal({
                pufETHAmount: pufETHAmount,
                pufETHToEthExchangeRate: uint128(exchangeRate),
                recipient: recipient
            })
        );

        emit WithdrawalRequested(batchIndex, pufETHAmount, recipient);
    }

    /**
     * @notice Finalizes the withdrawals up to the given batch index
     * @param withdrawalBatchIndex The index of the last batch to finalize
     * @dev Restricted to the Guardian
     */
    function finalizeWithdrawals(uint256 withdrawalBatchIndex) external restricted {
        WithdrawalManagerStorageStruct storage $ = _getWithdrawalManagerStorage();

        if (withdrawalBatchIndex <= $.finalizedWithdrawalBatch && withdrawalBatchIndex != 0) {
            revert BatchAlreadyFinalized();
        }

        for (uint256 i = $.finalizedWithdrawalBatch; i <= withdrawalBatchIndex;) {
            if ($.withdrawals.length < (i + 1) * BATCH_SIZE) {
                revert BatchNotFull();
            }

            //@audit how can this be manipulated?
            uint256 batchFinalizationExchangeRate = PUFFER_VAULT.convertToAssets(1 ether);

            WithdrawalBatch storage batch = $.withdrawalBatches[i];
            uint256 expectedETHAmount = batch.toTransfer;
            uint256 pufETHBurnAmount = batch.toBurn;

            uint256 ethAmount = (pufETHBurnAmount * batchFinalizationExchangeRate) / 1 ether;
            uint256 transferAmount = Math.min(expectedETHAmount, ethAmount);

            PUFFER_VAULT.transferETH(address(this), transferAmount);
            PUFFER_VAULT.burn(pufETHBurnAmount);

            batch.pufETHToEthExchangeRate = uint64(batchFinalizationExchangeRate);

            emit BatchFinalized(i, expectedETHAmount, transferAmount, pufETHBurnAmount);

            unchecked {
                ++i;
            }
        }
        $.finalizedWithdrawalBatch = withdrawalBatchIndex;
    }

    /**
     * @inheritdoc IWithdrawalManager
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function completeQueuedWithdrawal(uint256 withdrawalIdx) external restricted {
        WithdrawalManagerStorageStruct storage $ = _getWithdrawalManagerStorage();

        if (withdrawalIdx < $.finalizedWithdrawalBatch * BATCH_SIZE) {
            revert NotFinalized();
        }

        Withdrawal memory withdrawal = $.withdrawals[withdrawalIdx];
        uint256 batchSettlementExchangeRate = $.withdrawalBatches[withdrawalIdx / BATCH_SIZE].pufETHToEthExchangeRate;

        uint256 payoutExchangeRate = Math.min(withdrawal.pufETHToEthExchangeRate, batchSettlementExchangeRate);
        uint256 payoutAmount = (uint256(withdrawal.pufETHAmount) * payoutExchangeRate) / 1 ether;

        // remove data for some gas savings
        delete $.withdrawals[withdrawalIdx];

        emit WithdrawalCompleted(withdrawalIdx, payoutAmount, payoutExchangeRate, withdrawal.recipient);

        Address.sendValue(payable(withdrawal.recipient), payoutAmount);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
