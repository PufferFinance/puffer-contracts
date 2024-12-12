// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title SOON Token
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract SOON is ERC20, ERC20Permit {
    /**
     * @notice Constructor for the SOON token
     * totalSupply is 250 million SOON
     */
    constructor(address initialOwner) ERC20("Puffer Points", "SOON") ERC20Permit("Puffer Points") {
        _mint(initialOwner, 250_000_000 ether);
    }
}
