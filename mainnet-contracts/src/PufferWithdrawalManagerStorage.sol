// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title PufferWithdrawalManagerStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract PufferWithdrawalManagerStorage {
    /**
     * @notice A record to store requested withdrawals
     * @param pufETHAmount The amount of requested pufETH to withdraw
     * @param pufETHToETHExchangeRate The exchange rate from pufETH to ETH at the time of request
     * @param recipient The address that will receive the withdrawn ETH
     *
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct Withdrawal {
        uint128 pufETHAmount; // packed slot 0
        uint128 pufETHToETHExchangeRate; // packed slot 0
        address recipient; // slot 1
    }

    /**
     * @notice A record to store a batch of withdrawals at the time of finalization
     * @param pufETHToETHExchangeRate The exchange rate from pufETH to ETH at the time of finalization of the batch
     * @param toBurn The total amount of pufETH to burn
     * @param toTransfer The total amount of ETH to transfer
     *
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct WithdrawalBatch {
        uint64 pufETHToETHExchangeRate; // packed slot 0
        uint88 toBurn; // packed slot 0
        uint96 toTransfer; // packed slot 0
        uint128 withdrawalsClaimed; // packed slot 1
        uint128 amountClaimed; // packed slot 1
    }

    /**
     * @custom:storage-location erc7201:WithdrawalManager.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct WithdrawalManagerStorage {
        /**
         * @notice The maximum withdrawal amount
         */
        uint256 maxWithdrawalAmount;
        /**
         * @notice The current finalized withdrawal batch
         */
        uint256 finalizedWithdrawalBatch;
        /**
         * @notice The record of all requested withdrawals
         */
        Withdrawal[] withdrawals;
        /**
         * @notice The record of all finalized withdrawal batches
         */
        WithdrawalBatch[] withdrawalBatches;
    }

    /**
     * @dev Storage slot location for WithdrawalManager
     * @custom:storage-location erc7201:WithdrawalManager.storage
     * keccak256(abi.encode(uint256(keccak256("WithdrawalManager.storage")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant _WITHDRAWAL_MANAGER_STORAGE =
        0x2cc4e591e9323af22eeee6c9b0444863dad4345eb452e3c71b610fffca87e100;

    function _getWithdrawalManagerStorage() internal pure returns (WithdrawalManagerStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _WITHDRAWAL_MANAGER_STORAGE
        }
    }
}
