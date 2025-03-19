// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPufferNoRestakingValidator
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufferNoRestakingValidator {
    error WithdrawalAmountNotInGwei();
    error FailedToCreateWithdrawalRequest();
    error FailedToReadWithdrawalFee();
    error InvalidAmount();

    event ValidatorDeposited(bytes pubKey, uint256 ethAmount);
    event WithdrawalRequested(bytes pubKey, uint256 ethAmount);
}
