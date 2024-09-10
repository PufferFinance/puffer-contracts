// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PufferProtocol
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PUFI is ERC20, ERC20Permit, Pausable, Ownable {
    /**
     * @notice Thrown when a transfer is attempted while the token is paused
     */
    error PUFITransferPaused();

    /**
     * @notice Constructor for the PUFI token
     * totalSupply is 1 billion PUFI
     */
    constructor(address initialOwner) ERC20("PUFI", "PUFI") ERC20Permit("PUFI") Ownable(initialOwner) {
        _mint(initialOwner, 1_000_000_000 ether);

        _pause();
    }

    /**
     * @notice Unpauses the token
     * @dev Only the owner can unpause the token
     */
    function unpause() external virtual onlyOwner {
        _unpause();
    }

    /**
     * @notice Overrides the _update function to prevent token transfers
     * @dev We override the _update function to act like `_beforeTokenTransfer` hook
     */
    function _update(address from, address to, uint256 value) internal override {
        require(!paused() || owner() == _msgSender(), PUFITransferPaused());

        super._update(from, to, value);
    }
}
