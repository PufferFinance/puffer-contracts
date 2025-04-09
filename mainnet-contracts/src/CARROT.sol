// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title CARROT Token
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract CARROT is ERC20, ERC20Permit {
    /**
     * @notice Constructor for the CARROT token
     * totalSupply is 100 million CARROT
     */
    constructor(address initialOwner) ERC20("Carrot", "CARROT") ERC20Permit("Carrot") {
        _mint(initialOwner, 100_000_000 ether);
    }
}
