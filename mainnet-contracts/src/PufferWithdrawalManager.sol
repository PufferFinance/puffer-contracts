// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IPufferWithdrawalManager } from "./interface/IPufferWithdrawalManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Permit } from "./structs/Permit.sol";

/**
 * @title PufferWithdrawalManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PufferWithdrawalManager is IPufferWithdrawalManager, AccessManagedUpgradeable, UUPSUpgradeable {
    using SafeERC20 for address;

    /**
     * @dev The Puffer Vault contract address
     */
    PufferVaultV3 public immutable PUFFER_VAULT;

    uint256 missingETHLiquidity;

    uint256 pufETHToBurn; //@todo how to figure this out?

    uint256[] public withdrawals; // ETH amount to payout

    uint256 finalizedWithdrawalBatch;

    uint256 batchSize = 20;

    uint256[] public toBurn; // toBurn[0] = sum(first batchSize withdrawal amounts of pufETH)
    uint256[] public toTransfer; // toTransfer[0] = sum(first batchSize withdrawal amounts of ETH)
    uint256[] public exchangeRates; // toTransfer[0] = sum(first batchSize withdrawal amounts of ETH)

    constructor(PufferVaultV3 pufferVault) {
        PUFFER_VAULT = pufferVault;
        _disableInitializers();
    }

    receive() external payable { }

    /**
     * @notice Initializes the contract
     */
    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
    }

    /**
     * @notice Requests a withdrawal of ETH
     * @param pufETHAmount the amount of pufETH to be redeemed
     */
    function requestWithdrawal(uint256 pufETHAmount, address recipient) external returns (uint256 requestId){
        toBurn[withdrawals.length % batchSize] += pufETHAmount;

        uint256 expectedETHAmount = pufETHAmount; // 1:1 exchange rate

        toTransfer[withdrawals.length % batchSize] += pufETHAmount;

        withdrawals.push(expectedETHAmount);
        missingETHLiquidity += expectedETHAmount;
    }

    function finalizeWithdrawals(uint256 withdrawalBatchIndex) external {
        // if not %batchSize revert

        // get exchange rate here
        // and it is lower than the original one from requestWithdrawals ??                     1: 0.9 eth to pufeth

        // originalexpectedaamount was 10 eth
        // now it is 9 eth

        // record exchange rate here
        // exchangeRates[0] = 0.9;

        uint256 ethAmount = toTransfer[withdrawalBatchIndex];
        uint256 burnPufEThAMount = toBurn[withdrawalBatchIndex];

        // vault.transfer(address(this), ethAmount * newExchangeRate);
        // vault.burn(address(this), burnPufEThAMount); 

        finalizedWithdrawalBatch = withdrawalBatchIndex;

        // the etherscan tx should show that more pufETH is burned than the eth transfered amount
    }

    function completeQueuedWithdrawal(uint256 withdrawalIdx) external {
        if (withdrawalIdx < finalizedWithdrawalBatch * batchSize) {
            revert("not finalized");
        }

        // check the user exchange rate from the withdrawal request
       // check the settlement exchange rate from the finalizeWithdrawals
       // pay out using the lower 

        uint256 amount = withdrawals[withdrawalIdx]; // the user is expecting original amount
        withdrawals[withdrawalIdx] = 0;
        // eth.send(recipient, ethAmount * newExchangeRate))
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
