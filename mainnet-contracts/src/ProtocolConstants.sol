// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { Status } from "./struct/Status.sol";

abstract contract ProtocolConstants {
        /**
     * @notice Thrown when the deposit state that is provided doesn't match the one on Beacon deposit contract
     */
    error InvalidDepositRootHash();

    /**
     * @notice Thrown when the node operator tries to withdraw VTs from the PufferProtocol but has active/pending validators
     * @dev Signature "0x22242546"
     */
    error ActiveOrPendingValidatorsExist();

    /**
     * @notice Thrown on the module creation if the module already exists
     * @dev Signature "0x2157f2d7"
     */
    error ModuleAlreadyExists();

    /**
     * @notice Thrown when the new validators tires to register to a module, but the validator limit for that module is already reached
     * @dev Signature "0xb75c5781"
     */
    error ValidatorLimitForModuleReached();

    /**
     * @notice Thrown when the BLS public key is not valid
     * @dev Signature "0x7eef7967"
     */
    error InvalidBLSPubKey();

    /**
     * @notice Thrown when validator is not in a valid state
     * @dev Signature "0x3001591c"
     */
    error InvalidValidatorState(Status status);

    /**
     * @notice Thrown if the sender did not send enough ETH in the transaction
     * @dev Signature "0x242b035c"
     */
    error InvalidETHAmount();

    /**
     * @notice Thrown if the sender tries to register validator with invalid VT amount
     * @dev Signature "0x95c01f62"
     */
    error InvalidVTAmount();

    /**
     * @notice Thrown if the ETH transfer from the PufferModule to the PufferVault fails
     * @dev Signature "0x625a40e6"
     */
    error Failed();

    /**
     * @notice Thrown if the validator is not valid
     * @dev Signature "0x682a6e7c"
     */
    error InvalidValidator();

    /**
     * @notice Thrown if the input array length mismatch
     * @dev Signature "0x43714afd"
     */
    error InputArrayLengthMismatch();

    /**
     * @notice Thrown if the input array length is zero
     * @dev Signature "0x796cc525"
     */
    error InputArrayLengthZero();

    /**
     * @notice Thrown if the number of batches is 0 or greater than 64
     * @dev Signature "0x4ea54df9"
     */
    error InvalidNumberOfBatches();

    /**
     * @notice Thrown if the withdrawal amount is invalid
     * @dev Signature "0xdb73cdf0"
     */
    error InvalidWithdrawAmount();

    /**
     * @notice Thrown when the total epochs validated is invalid
     * @dev Signature "0x1af51909"
     */
    error InvalidTotalEpochsValidated();

    /**
     * @notice Thrown when the deadline is exceeded
     * @dev Signature "0xddff8620"
     */
    error DeadlineExceeded();

    /**
     * @dev BLS public keys are 48 bytes long
     */
    uint256 internal constant _BLS_PUB_KEY_LENGTH = 48;

    /**
     * @dev ETH Amount required to be deposited as a bond
     */
    uint256 internal constant _VALIDATOR_BOND = 1.5 ether;

    /**
     * @dev Minimum validation time in epochs (per batch number)
     * Roughly: 30 days * 225 epochs per day = 6750 epochs
     */
    uint256 internal constant _MINIMUM_EPOCHS_VALIDATION_REGISTRATION = 6750;

    /**
     * @dev Minimum validation time in epochs (per batch number)
     * Roughly: 5 days * 225 epochs per day = 1125 epochs
     */
    uint256 internal constant _MINIMUM_EPOCHS_VALIDATION_DEPOSIT = 1125;

    /**
     * @dev Maximum validation time in epochs (per batch number)
     * Roughly: 180 days * 225 epochs per day = 40500 epochs
     */
    uint256 internal constant _MAXIMUM_EPOCHS_VALIDATION_DEPOSIT = 40500;

    /**
     * @dev Number of epochs per day
     */
    uint256 internal constant _EPOCHS_PER_DAY = 225;

    /**
     * @dev Default "PUFFER_MODULE_0" module
     */
    bytes32 internal constant _PUFFER_MODULE_0 = bytes32("PUFFER_MODULE_0");

    /**
     * @dev 32 ETH in Gwei
     */
    uint256 internal constant _32_ETH_GWEI = 32 * 10 ** 9;

    bytes32 internal constant _FUNCTION_SELECTOR_REGISTER_VALIDATOR_KEY = IPufferProtocol.registerValidatorKey.selector;
    bytes32 internal constant _FUNCTION_SELECTOR_DEPOSIT_VALIDATION_TIME =
        IPufferProtocol.depositValidationTime.selector;
    bytes32 internal constant _FUNCTION_SELECTOR_REQUEST_WITHDRAWAL = IPufferProtocol.requestWithdrawal.selector;
    bytes32 internal constant _FUNCTION_SELECTOR_BATCH_HANDLE_WITHDRAWALS =
        IPufferProtocol.batchHandleWithdrawals.selector;
}