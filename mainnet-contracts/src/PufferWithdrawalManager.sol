// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPufferWithdrawalManager } from "./interface/IPufferWithdrawalManager.sol";
import { PufferWithdrawalManagerStorage } from "./PufferWithdrawalManagerStorage.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Permit } from "./structs/Permit.sol";

/**
 * @title PufferWithdrawalManager
 * @dev Manages the withdrawal process for the Puffer protocol
 */
contract PufferWithdrawalManager is
    IPufferWithdrawalManager,
    PufferWithdrawalManagerStorage,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    PufferVaultV3 public immutable PUFFER_VAULT;
    uint256 public constant BATCH_SIZE = 10;
    uint256 public constant MIN_WITHDRAWAL_AMOUNT = 0.01 ether;

    /**
     * @dev Constructor to initialize the PufferWithdrawalManager
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

        // Make the first batch empty, because the validations are weird for 0
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();
        for (uint256 i = 0; i < (BATCH_SIZE); ++i) {
            $.withdrawals.push(Withdrawal({ pufETHAmount: 0, pufETHToETHExchangeRate: 0, recipient: address(0) })); // Reserve the first index
        }
        $.withdrawalBatches.push(WithdrawalBatch({ toBurn: 0, toTransfer: 0, pufETHToETHExchangeRate: 0 }));
    }

    /**
     * @inheritdoc IPufferWithdrawalManager
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function requestWithdrawals(uint128 pufETHAmount, address recipient) external {
        PUFFER_VAULT.transferFrom(msg.sender, address(this), pufETHAmount);
        _processWithdrawalRequest(pufETHAmount, recipient);
    }

    /**
     * @notice Request withdrawals using permit
     * @param permitData The permit data for the withdrawal
     * @param recipient The address to receive the withdrawn ETH
     */
    function requestWithdrawalsWithPermit(Permit calldata permitData, address recipient) external {
        IERC20Permit(address(PUFFER_VAULT)).permit(
            msg.sender, address(this), permitData.amount, permitData.deadline, permitData.v, permitData.r, permitData.s
        );

        PUFFER_VAULT.transferFrom(msg.sender, address(this), permitData.amount);
        _processWithdrawalRequest(uint128(permitData.amount), recipient);
    }

    /**
     * @dev Internal function to process withdrawal requests
     * @param pufETHAmount The amount of pufETH to withdraw
     * @param recipient The address to receive the withdrawn ETH
     */
    function _processWithdrawalRequest(uint128 pufETHAmount, address recipient) internal {
        if (pufETHAmount < MIN_WITHDRAWAL_AMOUNT) {
            revert WithdrawalAmountTooLow();
        }
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();
        uint256 batchIndex = $.withdrawals.length / BATCH_SIZE;

        if (batchIndex == $.withdrawalBatches.length) {
            // Push empty batch when the batch is full
            $.withdrawalBatches.push(WithdrawalBatch({ toBurn: 0, toTransfer: 0, pufETHToETHExchangeRate: 0 }));
        }

        uint256 exchangeRate = PUFFER_VAULT.convertToAssets(1 ether);
        uint256 expectedETHAmount = pufETHAmount * exchangeRate / 1 ether;

        WithdrawalBatch storage batch = $.withdrawalBatches[batchIndex];
        batch.toBurn += uint96(pufETHAmount);
        batch.toTransfer += uint96(expectedETHAmount);

        uint256 withdrawalIndex = $.withdrawals.length;

        // Update the withdrawal
        $.withdrawals.push(
            Withdrawal({
                pufETHAmount: pufETHAmount,
                pufETHToETHExchangeRate: uint128(exchangeRate),
                recipient: recipient
            })
        );

        emit WithdrawalRequested(withdrawalIndex, batchIndex, pufETHAmount, recipient);
    }

    /**
     * @notice Finalizes the withdrawals up to the given batch index
     * @param withdrawalBatchIndex The index of the last batch to finalize
     * @dev Restricted to the Guardian
     */
    function finalizeWithdrawals(uint256 withdrawalBatchIndex) external restricted {
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();

        if ((withdrawalBatchIndex + 1) * BATCH_SIZE > $.withdrawals.length) {
            revert BatchNotFull();
        }

        if (withdrawalBatchIndex <= $.finalizedWithdrawalBatch && withdrawalBatchIndex != 0) {
            revert BatchAlreadyFinalized();
        }

        for (uint256 i = $.finalizedWithdrawalBatch; i <= withdrawalBatchIndex;) {
            //@audit how can this be manipulated?
            uint256 batchFinalizationExchangeRate = PUFFER_VAULT.convertToAssets(1 ether);

            WithdrawalBatch storage batch = $.withdrawalBatches[i];
            uint256 expectedETHAmount = batch.toTransfer;
            uint256 pufETHBurnAmount = batch.toBurn;

            uint256 ethAmount = (pufETHBurnAmount * batchFinalizationExchangeRate) / 1 ether;
            uint256 transferAmount = Math.min(expectedETHAmount, ethAmount);

            PUFFER_VAULT.transferETH(address(this), transferAmount);
            PUFFER_VAULT.burn(pufETHBurnAmount);

            batch.pufETHToETHExchangeRate = uint64(batchFinalizationExchangeRate);

            emit BatchFinalized(i, expectedETHAmount, transferAmount, pufETHBurnAmount);

            unchecked {
                ++i;
            }
        }
        $.finalizedWithdrawalBatch = withdrawalBatchIndex;
    }

    /**
     * @inheritdoc IPufferWithdrawalManager
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function completeQueuedWithdrawal(uint256 withdrawalIdx) external restricted {
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();

        uint256 batchIndex = withdrawalIdx / BATCH_SIZE;
        if (batchIndex > $.finalizedWithdrawalBatch) {
            revert NotFinalized();
        }

        if (withdrawalIdx >= $.withdrawals.length) {
            revert InvalidWithdrawalIndex();
        }

        Withdrawal storage withdrawal = $.withdrawals[withdrawalIdx];

        // Check if the withdrawal has already been completed
        if (withdrawal.recipient == address(0)) {
            revert WithdrawalAlreadyCompleted();
        }

        uint256 batchSettlementExchangeRate = $.withdrawalBatches[batchIndex].pufETHToETHExchangeRate;

        uint256 payoutExchangeRate = Math.min(withdrawal.pufETHToETHExchangeRate, batchSettlementExchangeRate);
        uint256 payoutAmount = (uint256(withdrawal.pufETHAmount) * payoutExchangeRate) / 1 ether;

        address recipient = withdrawal.recipient;

        // remove data for some gas savings
        delete $.withdrawals[withdrawalIdx];

        emit WithdrawalCompleted(withdrawalIdx, payoutAmount, payoutExchangeRate, recipient);

        Address.sendValue(payable(recipient), payoutAmount);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
