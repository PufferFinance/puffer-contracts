// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { PufLockerStorage } from "./PufLockerStorage.sol";
import { IPufLocker } from "./interface/IPufLocker.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Permit } from "./structs/Permit.sol";
import { InvalidAmount } from "./Errors.sol";

/**
 * @title PufLocker
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PufLocker is IPufLocker, AccessManagedUpgradeable, UUPSUpgradeable, PufLockerStorage {
    using SafeERC20 for IERC20;

    constructor() {
        _disableInitializers();
    }

    function initialize(address accessManager) external initializer {
        require(accessManager != address(0));
        __AccessManaged_init(accessManager);
    }

    modifier isAllowedToken(address token) {
        PufLockerData storage $ = _getPufLockerStorage();
        if (!$.allowedTokens[token]) {
            revert TokenNotAllowed();
        }
        _;
    }

    /**
     * @inheritdoc IPufLocker
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function deposit(address token, address recipient, uint128 lockPeriod, Permit calldata permitData)
        external
        isAllowedToken(token)
        restricted
    {
        if (permitData.amount == 0) {
            revert InvalidAmount();
        }
        PufLockerData storage $ = _getPufLockerStorage();

        if (lockPeriod < $.minLockPeriod || lockPeriod > $.maxLockPeriod) {
            revert InvalidLockPeriod();
        }

        // The users that use a smart wallet and do not use the Permit and they do the .approve and then .deposit.
        // They might get confused when they open Etherscan, and see:
        // "Although one or more Error Occurred [execution reverted] Contract Execution Completed"

        // To avoid that, we don't want to call the permit function if it is not necessary.
        if (permitData.deadline >= block.timestamp) {
            // https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#security_considerations
            try ERC20Permit(token).permit({
                owner: msg.sender,
                spender: address(this),
                value: permitData.amount,
                deadline: permitData.deadline,
                v: permitData.v,
                s: permitData.s,
                r: permitData.r
            }) { } catch { }
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), permitData.amount);

        uint128 releaseTime = uint128(block.timestamp) + lockPeriod;

        $.deposits[recipient][token].push(Deposit(uint128(permitData.amount), releaseTime));

        emit Deposited(recipient, token, uint128(permitData.amount), releaseTime);
    }

    /**
     * @inheritdoc IPufLocker
     */
    function withdraw(address token, uint256[] calldata depositIndexes, address recipient) external {
        if (recipient == address(0)) {
            revert InvalidRecipientAddress();
        }

        PufLockerData storage $ = _getPufLockerStorage();

        uint128 totalAmount = 0;
        Deposit[] storage userDeposits = $.deposits[msg.sender][token];

        // nosemgrep array-length-outside-loop
        for (uint256 i = 0; i < depositIndexes.length; ++i) {
            uint256 index = depositIndexes[i];
            // nosemgrep array-length-outside-loop
            if (index >= userDeposits.length) {
                revert InvalidDepositIndex();
            }

            Deposit storage userDeposit = userDeposits[index];
            if (userDeposit.releaseTime > uint128(block.timestamp)) {
                revert DepositLocked();
            }

            totalAmount += userDeposit.amount;
            userDeposit.amount = 0; // Set amount to zero to mark as withdrawn
        }

        if (totalAmount == 0) {
            revert NoWithdrawableAmount();
        }

        IERC20(token).safeTransfer(recipient, totalAmount);

        emit Withdrawn({ user: msg.sender, token: token, amount: totalAmount, recipient: recipient });
    }

    /**
     * @notice Creates a new staking token contract
     * @dev Restricted to Puffer DAO
     */
    function setIsAllowedToken(address token, bool allowed) external restricted {
        PufLockerData storage $ = _getPufLockerStorage();
        $.allowedTokens[token] = allowed;
        emit SetTokenIsAllowed(token, allowed);
    }

    /**
     * @notice Creates a new staking token contract
     * @dev Restricted to Puffer DAO
     */
    function setLockPeriods(uint128 minLock, uint128 maxLock) external restricted {
        if (minLock > maxLock) {
            revert InvalidLockPeriod();
        }
        PufLockerData storage $ = _getPufLockerStorage();
        emit LockPeriodsChanged($.minLockPeriod, minLock, $.maxLockPeriod, maxLock);
        $.minLockPeriod = minLock;
        $.maxLockPeriod = maxLock;
    }

    /**
     * @inheritdoc IPufLocker
     */
    function getDeposits(address user, address token, uint256 start, uint256 limit)
        external
        view
        returns (Deposit[] memory)
    {
        PufLockerData storage $ = _getPufLockerStorage();
        Deposit[] storage userDeposits = $.deposits[user][token];
        uint256 totalDeposits = userDeposits.length;
        Deposit[] memory depositPage;

        if (start >= totalDeposits) {
            return depositPage;
        }

        uint256 end = start + limit > totalDeposits ? totalDeposits : start + limit;
        // nosemgrep basic-arithmetic-underflow
        uint256 count = end - start;

        depositPage = new Deposit[](count);
        for (uint256 i = 0; i < count; ++i) {
            depositPage[i] = userDeposits[start + i];
        }

        return depositPage;
    }

    /**
     * @inheritdoc IPufLocker
     */
    function getAllDeposits(address token, address depositor) external view returns (Deposit[] memory) {
        PufLockerData storage $ = _getPufLockerStorage();
        return $.deposits[depositor][token];
    }

    /**
     * @inheritdoc IPufLocker
     */
    function getLockPeriods() external view returns (uint128, uint128) {
        PufLockerData storage $ = _getPufLockerStorage();
        return ($.minLockPeriod, $.maxLockPeriod);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
