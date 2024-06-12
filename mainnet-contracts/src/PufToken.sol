// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract puffStakingContract is ERC20, ERC20Permit {
    constructor(address token, string memory tokenName, string memory tokenSymbol)
        ERC20(tokenName, tokenSymbol)
        ERC20Permit(tokenName)
    { 
    }

    function deposit(address to, uint256 amount) external {
        // safe transfer from msg.sender()
        // _mint(to, amount ** upscale to 18)
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    /**
     * @notice Migrates the tokens using the allowlisted migrator contract
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function migrate(address[] calldata tokens, address migratorContract, address destination) external restricted {
        _migrate({ depositor: msg.sender, destination: destination, migratorContract: migratorContract, tokens: tokens });
    }
}