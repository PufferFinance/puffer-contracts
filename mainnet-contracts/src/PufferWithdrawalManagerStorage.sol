// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title PufferWithdrawalManagerStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract PufferWithdrawalManagerStorage {
        /**
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct Withdrawal {
        uint128 pufETHAmount; // packed slot 0
        uint128 pufETHToETHExchangeRate; // packed slot 0
        address recipient; //160bits packed slot 1
    }
    struct WithdrawalBatch {
        uint64 pufETHToETHExchangeRate; // packed slot 0
        uint96 toBurn; // packed slot 0
        uint96 toTransfer; // packed slot 0
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
        uint256 finalizedWithdrawalBatch;
        Withdrawal[] withdrawals;
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
