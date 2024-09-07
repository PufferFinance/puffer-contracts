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
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IWETH } from "../src/interface/Other/IWETH.sol";

/**
 * @title PufferWithdrawalManager
 * @custom:security-contact security@puffer.fi
 */
contract PufferWithdrawalManager is
    IPufferWithdrawalManager,
    PufferWithdrawalManagerStorage,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    using SafeCast for uint256;

    /**
     * @notice The batch size for the withdrawal manager
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    PufferVaultV3 public immutable PUFFER_VAULT;
    /**
     * @notice The minimum withdrawal amount
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    uint256 public constant MIN_WITHDRAWAL_AMOUNT = 0.01 ether;
    /**
     * @notice The WETH contract
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IWETH public immutable WETH;
    /**
     * @notice The batch size for the withdrawal manager
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    uint256 public immutable BATCH_SIZE;

    /**
     * @dev Constructor to initialize the PufferWithdrawalManager
     * @param pufferVault Address of the PufferVaultV3 contract
     * @param weth Address of the WETH contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(uint256 batchSize, PufferVaultV3 pufferVault, IWETH weth) {
        BATCH_SIZE = batchSize;
        PUFFER_VAULT = pufferVault;
        WETH = weth;
        _disableInitializers();
    }

    receive() external payable { }

    /**
     * @notice Initializes the contract
     */
    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);

        // Make the first `batch size` withdrawals empty, because the validations are weird for 0 batch
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();

        // Initially, we don't care about the multiplier, we want to skip the first batch [0]
        for (uint256 i = 0; i < BATCH_SIZE; ++i) {
            $.withdrawals.push(Withdrawal({ pufETHAmount: 0, pufETHToETHExchangeRate: 0, recipient: address(0) }));
        }
        $.withdrawalBatches.push(WithdrawalBatch({ toBurn: 0, toTransfer: 0, pufETHToETHExchangeRate: 0 }));
        $.finalizedWithdrawalBatch = 0; // do it explicitly
    }

    /**
     * @inheritdoc IPufferWithdrawalManager
     * @dev Restricted in this context is like the `whenNotPaused` modifier from Pausable.sol
     */
    function requestWithdrawal(uint128 pufETHAmount, address recipient) external restricted {
        _processWithdrawalRequest(pufETHAmount, recipient);
    }

    /**
     * @inheritdoc IPufferWithdrawalManager
     * @dev Restricted in this context is like the `whenNotPaused` modifier from Pausable.sol
     */
    function requestWithdrawalWithPermit(Permit calldata permitData, address recipient) external restricted {
        try IERC20Permit(address(PUFFER_VAULT)).permit({
            owner: msg.sender,
            spender: address(this),
            value: permitData.amount,
            deadline: permitData.deadline,
            v: permitData.v,
            s: permitData.s,
            r: permitData.r
        }) { } catch { }

        _processWithdrawalRequest(uint128(permitData.amount), recipient);
    }

    /**
     * @notice Finalizes the withdrawals up to the given batch index
     * @param withdrawalBatchIndex The index of the last batch to finalize
     * @dev Restricted access to ROLE_ID_WITHDRAWAL_FINALIZER
     */
    function finalizeWithdrawals(uint256 withdrawalBatchIndex) external restricted {
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();

        // Check if all the batches that we want to finalize are full
        require(withdrawalBatchIndex < $.withdrawals.length / BATCH_SIZE, BatchesAreNotFull());

        uint256 finalizedWithdrawalBatch = $.finalizedWithdrawalBatch;

        require(withdrawalBatchIndex > finalizedWithdrawalBatch, BatchAlreadyFinalized(withdrawalBatchIndex));

        // Start from the finalized batch + 1 and go up to the given batch index
        for (uint256 i = finalizedWithdrawalBatch + 1; i <= withdrawalBatchIndex; ++i) {
            uint256 batchFinalizationExchangeRate = PUFFER_VAULT.convertToAssets(1 ether);

            WithdrawalBatch storage batch = $.withdrawalBatches[i];

            uint256 expectedETHAmount = batch.toTransfer;
            uint256 pufETHBurnAmount = batch.toBurn;

            uint256 ethAmount = (pufETHBurnAmount * batchFinalizationExchangeRate) / 1 ether;
            uint256 transferAmount = Math.min(expectedETHAmount, ethAmount);

            PUFFER_VAULT.transferETH(address(this), transferAmount);
            PUFFER_VAULT.burn(pufETHBurnAmount);

            batch.pufETHToETHExchangeRate = uint64(batchFinalizationExchangeRate);

            emit BatchFinalized({
                batchIdx: i,
                expectedETHAmount: expectedETHAmount,
                actualEthAmount: transferAmount,
                pufETHBurnAmount: pufETHBurnAmount
            });
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
        require(batchIndex <= $.finalizedWithdrawalBatch, NotFinalized());

        Withdrawal storage withdrawal = $.withdrawals[withdrawalIdx];

        // Check if the withdrawal has already been completed
        require(withdrawal.recipient != address(0), WithdrawalAlreadyCompleted());

        uint256 batchSettlementExchangeRate = $.withdrawalBatches[batchIndex].pufETHToETHExchangeRate;

        uint256 payoutExchangeRate = Math.min(withdrawal.pufETHToETHExchangeRate, batchSettlementExchangeRate);
        uint256 payoutAmount = (uint256(withdrawal.pufETHAmount) * payoutExchangeRate) / 1 ether;

        address recipient = withdrawal.recipient;

        // remove data for some gas savings
        delete $.withdrawals[withdrawalIdx];

        // Wrap ETH to WETH
        WETH.deposit{ value: payoutAmount }();

        WETH.transfer(recipient, payoutAmount);

        emit WithdrawalCompleted({
            withdrawalIdx: withdrawalIdx,
            ethPayoutAmount: payoutAmount,
            payoutExchangeRate: payoutExchangeRate,
            recipient: recipient
        });
    }

    /**
     * @inheritdoc IPufferWithdrawalManager
     */
    function getFinalizedWithdrawalBatch() external view returns (uint256) {
        return _getWithdrawalManagerStorage().finalizedWithdrawalBatch;
    }

    /**
     * @inheritdoc IPufferWithdrawalManager
     */
    function getWithdrawalsLength() external view returns (uint256) {
        return _getWithdrawalManagerStorage().withdrawals.length;
    }

    /**
     * @inheritdoc IPufferWithdrawalManager
     */
    function getWithdrawal(uint256 withdrawalIdx) external view returns (Withdrawal memory) {
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();
        // We don't want panic when the caller passes an invalid withdrawalIdx
        if (withdrawalIdx >= $.withdrawals.length) {
            return Withdrawal(0, 0, address(0));
        }
        return $.withdrawals[withdrawalIdx];
    }

    /**
     * @param pufETHAmount The amount of pufETH to withdraw
     * @param recipient The address to receive the withdrawn ETH
     */
    function _processWithdrawalRequest(uint128 pufETHAmount, address recipient) internal {
        require(pufETHAmount >= MIN_WITHDRAWAL_AMOUNT, WithdrawalAmountTooLow());

        // Always transfer from the msg.sender
        PUFFER_VAULT.transferFrom(msg.sender, address(this), pufETHAmount);

        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();

        uint256 withdrawalIndex = $.withdrawals.length;

        uint256 batchIndex = withdrawalIndex / BATCH_SIZE;

        if (batchIndex == $.withdrawalBatches.length) {
            // Push empty batch when the previous batch is full
            $.withdrawalBatches.push(WithdrawalBatch({ toBurn: 0, toTransfer: 0, pufETHToETHExchangeRate: 0 }));
        }

        uint256 pufETHToETHExchangeRate = PUFFER_VAULT.convertToAssets(1 ether);
        uint256 expectedETHAmount = pufETHAmount * pufETHToETHExchangeRate / 1 ether;

        WithdrawalBatch storage batch = $.withdrawalBatches[batchIndex];
        batch.toBurn += uint96(pufETHAmount);
        batch.toTransfer += uint96(expectedETHAmount);

        $.withdrawals.push(
            Withdrawal({
                pufETHAmount: pufETHAmount,
                recipient: recipient,
                pufETHToETHExchangeRate: pufETHToETHExchangeRate.toUint128()
            })
        );

        emit WithdrawalRequested({
            withdrawalIdx: withdrawalIndex,
            batchIdx: batchIndex,
            pufETHAmount: pufETHAmount,
            recipient: recipient
        });
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted {
        PufferWithdrawalManager newImplementationContract = PufferWithdrawalManager(payable(newImplementation));

        require(newImplementationContract.BATCH_SIZE() == BATCH_SIZE, BatchSizeCannotChange());
    }
}
