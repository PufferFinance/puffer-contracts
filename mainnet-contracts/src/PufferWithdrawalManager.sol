// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IPufferWithdrawalManager } from "./interface/IPufferWithdrawalManager.sol";
import { PufferWithdrawalManagerStorage } from "./PufferWithdrawalManagerStorage.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Permit } from "./structs/Permit.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IWETH } from "../src/interface/Other/IWETH.sol";
import { TransferFailed } from "./Errors.sol";

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

    // keccak256(abi.encode(uint256(keccak256("pufferWithdrawalManager.withdrawalRequest")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _WITHDRAWAL_REQUEST_TRACKER_LOCATION =
        0xa4e2950800ad48b89d951842a006c666c0b29f755b9face41cad0b8d83328900;

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
     * @notice Only one withdrawal request per transaction is allowed
     */
    modifier oneWithdrawalRequestAllowed() virtual {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // If the deposit tracker location is set to `1`, revert with `MultipleWithdrawalsAreForbidden()`
            if tload(_WITHDRAWAL_REQUEST_TRACKER_LOCATION) {
                mstore(0x00, 0x0eca04b2) // Store the error signature `0x0eca04b2` for `error MultipleWithdrawalsAreForbidden()` in memory.
                revert(0x1c, 0x04) // Revert by returning those 4 bytes. `revert MultipleWithdrawalsAreForbidden()`
            }
        }
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tstore(_WITHDRAWAL_REQUEST_TRACKER_LOCATION, 1) // Store `1` in the deposit tracker location
        }
        _;
    }

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
        $.withdrawalBatches.push(
            WithdrawalBatch({
                toBurn: 0,
                toTransfer: 0,
                pufETHToETHExchangeRate: 0,
                withdrawalsClaimed: 0,
                amountClaimed: 0
            })
        );
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

            uint256 transferAmount = _calculateBatchTransferAmount({
                pufETHBurnAmount: pufETHBurnAmount,
                batchFinalizationExchangeRate: batchFinalizationExchangeRate,
                expectedETHAmount: expectedETHAmount
            });

            PUFFER_VAULT.transferETH(address(this), transferAmount);
            PUFFER_VAULT.burn(pufETHBurnAmount);

            batch.pufETHToETHExchangeRate = batchFinalizationExchangeRate.toUint64();

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
     * @dev Restricted access to ROLE_ID_WITHDRAWAL_FINALIZER
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

        // When a withdrawal is completed, we need to update the batch's claimed withdrawals and amount claimed
        // When all withdrawals from the batch are completed, the dust can be returned to the vault by calling `returnExcessETHToVault`

        ++$.withdrawalBatches[batchIndex].withdrawalsClaimed;
        $.withdrawalBatches[batchIndex].amountClaimed += payoutAmount.toUint128();
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
     * @dev Restricted access to ROLE_ID_OPERATIONS_MULTISIG
     */
    function returnExcessETHToVault(uint256[] calldata batchIndices) external restricted {
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();
        uint256 totalExcessETH = 0;

        for (uint256 i = 0; i < batchIndices.length; ++i) {
            WithdrawalBatch storage batch = $.withdrawalBatches[batchIndices[i]];

            require(batch.withdrawalsClaimed == BATCH_SIZE, NotAllWithdrawalsClaimed());
            require(batch.amountClaimed != batch.toTransfer, AlreadyReturned());

            uint256 expectedETHAmount = batch.toTransfer;
            uint256 pufETHBurnAmount = batch.toBurn;

            uint256 transferAmount = _calculateBatchTransferAmount({
                pufETHBurnAmount: pufETHBurnAmount,
                batchFinalizationExchangeRate: batch.pufETHToETHExchangeRate,
                expectedETHAmount: expectedETHAmount
            });

            // nosemgrep basic-arithmetic-underflow
            uint256 diff = transferAmount - batch.amountClaimed;
            totalExcessETH += diff;

            // Update the amount claimed to the total toTransfer amount to prevent calling this function twice (validation line 239)
            batch.amountClaimed = batch.toTransfer;
        }

        if (totalExcessETH > 0) {
            // nosemgrep arbitrary-low-level-call
            (bool success,) = address(PUFFER_VAULT).call{ value: totalExcessETH }("");
            require(success, TransferFailed());

            emit ExcessETHReturned(batchIndices, totalExcessETH);
        }
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
     * @inheritdoc IPufferWithdrawalManager
     */
    function getBatch(uint256 batchIdx) external view returns (WithdrawalBatch memory) {
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();
        // We don't want panic when the caller passes an invalid batchIdx
        if (batchIdx >= $.withdrawalBatches.length) {
            return WithdrawalBatch({
                toBurn: 0,
                toTransfer: 0,
                pufETHToETHExchangeRate: 0,
                withdrawalsClaimed: 0,
                amountClaimed: 0
            });
        }
        return $.withdrawalBatches[batchIdx];
    }

    /**
     * @param pufETHAmount The amount of pufETH to withdraw
     * @param recipient The address to receive the withdrawn ETH
     */
    function _processWithdrawalRequest(uint128 pufETHAmount, address recipient) internal oneWithdrawalRequestAllowed {
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();

        require(pufETHAmount >= MIN_WITHDRAWAL_AMOUNT, WithdrawalAmountTooLow());
        require(pufETHAmount <= $.maxWithdrawalAmount, WithdrawalAmountTooHigh());
        require(recipient != address(0), WithdrawalToZeroAddress());

        // Always transfer from the msg.sender
        PUFFER_VAULT.transferFrom(msg.sender, address(this), pufETHAmount);

        uint256 withdrawalIndex = $.withdrawals.length;

        uint256 batchIndex = withdrawalIndex / BATCH_SIZE;

        if (batchIndex == $.withdrawalBatches.length) {
            // Push empty batch when the previous batch is full
            $.withdrawalBatches.push(
                WithdrawalBatch({
                    toBurn: 0,
                    toTransfer: 0,
                    pufETHToETHExchangeRate: 0,
                    withdrawalsClaimed: 0,
                    amountClaimed: 0
                })
            );
        }

        uint256 pufETHToETHExchangeRate = PUFFER_VAULT.convertToAssets(1 ether);
        uint256 expectedETHAmount = pufETHAmount * pufETHToETHExchangeRate / 1 ether;

        WithdrawalBatch storage batch = $.withdrawalBatches[batchIndex];
        batch.toBurn += uint88(pufETHAmount);
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
     * @notice Changes the max withdrawal amount
     * @param newMaxWithdrawalAmount The new max withdrawal amount
     * @dev Restricted access to ROLE_ID_DAO
     */
    function changeMaxWithdrawalAmount(uint256 newMaxWithdrawalAmount) external restricted {
        WithdrawalManagerStorage storage $ = _getWithdrawalManagerStorage();
        require(newMaxWithdrawalAmount > MIN_WITHDRAWAL_AMOUNT, InvalidMaxWithdrawalAmount());
        emit MaxWithdrawalAmountChanged($.maxWithdrawalAmount, newMaxWithdrawalAmount);
        $.maxWithdrawalAmount = newMaxWithdrawalAmount;
    }

    /**
     * @inheritdoc IPufferWithdrawalManager
     * @return The max withdrawal amount
     */
    function getMaxWithdrawalAmount() external view returns (uint256) {
        return _getWithdrawalManagerStorage().maxWithdrawalAmount;
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

    function _calculateBatchTransferAmount(
        uint256 pufETHBurnAmount,
        uint256 batchFinalizationExchangeRate,
        uint256 expectedETHAmount
    ) internal pure returns (uint256) {
        uint256 batchFinalizationAmount = (pufETHBurnAmount * batchFinalizationExchangeRate) / 1 ether;
        return Math.min(expectedETHAmount, batchFinalizationAmount);
    }
}
