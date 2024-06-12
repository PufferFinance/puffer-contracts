// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IWETH } from "./interface/IWETH.sol";
import { IMigrator } from "./interface/IMigrator.sol";
import { Permit } from "./structs/Permit.sol";

/**
 * @title Puffer L2 Staking Pool
 * @author Puffer Finance
 * @notice PufferL2StakingPool
 * @custom:security-contact security@puffer.fi
 */
contract PufferL2Depositor is AccessManaged {
    constructor(address accessManager) AccessManaged(accessManager) { }

    // restricted to PUffer Dao
    function addNewToken(address token) external restricted {
        // string memory tokenName = strings.contact("puf..");
        // new pufETHPermit(token);
    }

    function deposit(address token) external {
        // if (!allowedTokens[token]) revert
        // safeTransferFrom(token, msg.sender, amount)
        // token.deposit(msg.sender, ..)
    }
}
