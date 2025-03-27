// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

contract MockWithdrawalRequestPredeploy {
    event MockWithdrawalRequestPredeployFallback(uint256 amount);

    fallback() external payable {
        emit MockWithdrawalRequestPredeployFallback(msg.value);
    }
}
