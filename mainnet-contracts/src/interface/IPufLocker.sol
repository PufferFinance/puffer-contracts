// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Permit } from "../structs/Permit.sol";

interface IPufLocker {
    // Custom error messages
    error TokenNotAllowed();
    error InvalidAmount();
    error InvalidLockPeriod();
    error InvalidDepositIndex();
    error DepositStillLocked();
    error NoWithdrawableAmount();
    error InvalidRecipientAddress();

    // Events
    event SetTokenIsAllowed(address indexed token, bool allowed);
    event Deposited(address indexed user, address indexed token, uint128 amount, uint128 releaseTime);
    event Withdrawn(address indexed user, address indexed token, uint128 amount, address recipient);
    event LockPeriodsChanged(uint128 previousMinLock, uint128 newMinLock, uint128 previousMaxLock, uint128 newMaxLock);

    // Functions
    function setIsAllowedToken(address token, bool allowed) external;

    function setLockPeriods(uint128 minLockPeriod, uint128 maxLockPeriod) external;

    function deposit(address token, uint128 lockPeriod, Permit calldata permitData) external;

    function withdraw(address token, uint256[] calldata depositIndexes, address recipient) external;

    function getDeposits(address user, address token, uint256 start, uint256 limit)
        external
        view
        returns (Deposit[] memory);
    function getLockPeriods() external view returns (uint128, uint128);

    struct Deposit {
        uint128 amount;
        uint128 releaseTime;
    }
}
