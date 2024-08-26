// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title WithdrawalManagerStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract WithdrawalManagerStorage {
    struct Withdrawal {
        // 96bits
        uint128 pufETHAmount; 
        uint128 pufETHToEthExchangeRate;
        address recipient; //160bits
    }

    struct WithdrawalBatch {
        uint64 pufETHToEthExchangeRate;
        uint96 toBurn;
        uint96 toTransfer;
    }

    /**
     * @custom:storage-location erc7201:WithdrawalManager.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct WithdrawalManagerStorageStruct {
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

    function _getWithdrawalManagerStorage() internal pure returns (WithdrawalManagerStorageStruct storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _WITHDRAWAL_MANAGER_STORAGE
        }
    }
}
