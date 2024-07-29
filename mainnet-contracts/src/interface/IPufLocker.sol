// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Permit } from "../structs/Permit.sol";

/**
 * @title IPufStakingPool
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufLocker {
    struct Deposit {
        uint128 amount;
        uint128 releaseTime;
    }

    /**
     * @notice Thrown when the token is not allowed
     * @dev Signature "0xa29c4986"
     */
    error TokenNotAllowed();

    /**
     * @notice Thrown when lock period is not in the valid range
     * @dev Signature "0x2a82a34f"
     */
    error InvalidLockPeriod();

    /**
     * @notice Thrown index of the deposit is invalid
     * @dev Signature "0x6d97cdda"
     */
    error InvalidDepositIndex();

    /**
     * @notice Thrown when the deposit is locked
     * @dev Signature "0xf38b9b5b"
     */
    error DepositLocked();

    /**
     * @notice Thrown when there is no withdrawable amount
     * @dev Signature "0x1b1d7861"
     */
    error NoWithdrawableAmount();

    /**
     * @notice Thrown when the recipient address is invalid
     * @dev Signature "0x44d99fea"
     */
    error InvalidRecipientAddress();

    /**
     * @notice Event emitted when a token is allowed or disallowed
     * @param token The address of the token
     * @param allowed Whether the token is allowed or not
     */
    event SetTokenIsAllowed(address indexed token, bool allowed);

    /**
     * @notice Event emitted when funds are deposited into the locker
     * @param user The address of the user who initiated the deposit
     * @param token The address of the token being deposited
     * @param amount The amount of tokens being deposited
     * @param releaseTime The release time of the deposit
     */
    event Deposited(address indexed user, address indexed token, uint128 amount, uint128 releaseTime);

    /**
     * @notice Event emitted when funds are withdrawn from the locker
     * @param user The address of the user who initiated the withdrawal
     * @param token The address of the token being withdrawn
     * @param amount The amount of tokens being withdrawn
     * @param recipient The address that will receive the withdrawn funds
     */
    event Withdrawn(address indexed user, address indexed token, uint128 amount, address indexed recipient);

    /**
     * @notice Event emitted when the lock periods are changed
     * @param previousMinLock The previous minimum lock period
     * @param newMinLock The new minimum lock period
     * @param previousMaxLock The previous maximum lock period
     * @param newMaxLock The new maximum lock period
     */
    event LockPeriodsChanged(uint128 previousMinLock, uint128 newMinLock, uint128 previousMaxLock, uint128 newMaxLock);

    /**
     * @notice Deposit tokens into the locker
     * @param token The address of the token to deposit
     * @param token The address of the recipient
     * @param lockPeriod The lock period for the deposit
     * @param permitData The permit data for the deposit
     */
    function deposit(address token, address recipient, uint128 lockPeriod, Permit calldata permitData) external;

    /**
     * @notice Withdraws specified deposits for a given token and transfers the funds to the recipient
     * @dev If the deposit is still locked, the function will revert
     * @param token The address of the token
     * @param depositIndexes An array of deposit indexes to be withdrawn
     * @param recipient The address to receive the withdrawn funds
     */
    function withdraw(address token, uint256[] calldata depositIndexes, address recipient) external;

    /**
     * @notice Get deposits for a specific user and token
     * @dev Amount == 0 && releaseTime > 0 = the deposit got withdrawn
     * @param user The address of the user
     * @param token The address of the token
     * @param start The starting index of the deposits
     * @param limit The maximum number of deposits to retrieve
     * @return deposits An array of Deposit structs representing the deposits
     */
    function getDeposits(address user, address token, uint256 start, uint256 limit)
        external
        view
        returns (Deposit[] memory);

    /**
     * @notice Get all deposits for a specific token and depositor
     * @dev Amount == 0 && releaseTime > 0 = the deposit got withdrawn
     * @param token The address of the token
     * @param depositor The address of the depositor
     * @return deposits An array of Deposit structs representing the deposits
     */
    function getAllDeposits(address token, address depositor) external view returns (Deposit[] memory);

    /**
     * @notice Get the minimum and maximum lock periods allowed for deposits
     * @return minLock The minimum lock period
     * @return maxLock The maximum lock period
     */
    function getLockPeriods() external view returns (uint128 minLock, uint128 maxLock);
}
