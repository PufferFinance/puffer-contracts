// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPufferWithdrawalManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufferWithdrawalManager {
    function requestWithdrawal(uint256 pufETHAmount, address recipient) external returns (uint256 requestId);
    function finalizeWithdrawals(uint256 withdrawalBatchIndex) external;
    function completeQueuedWithdrawal(uint256 withdrawalIdx) external;
}
