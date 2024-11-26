// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
//solhint-disable-next-line no-unused-import
import { Votes } from "@openzeppelin/contracts/governance/utils/Votes.sol";

/**
 * @title PUFFER Token
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PUFFER is ERC20Votes, ERC20Permit, Pausable, Ownable {
    /**
     * @notice Thrown when a transfer is attempted while the token is paused
     */
    error TransferPaused();

    /**
     * @notice Event emitted when the allowedFrom status of an address is set
     * @param from The address that is allowed to transfer tokens
     * @param isAllowedFrom Whether the address is allowed to transfer tokens
     */
    event SetAllowedFrom(address indexed from, bool isAllowedFrom);

    /**
     * @notice Event emitted when the allowedTo status of an address is set
     * @param to The address that is allowed to receive tokens
     * @param isAllowedTo Whether the address is allowed to receive tokens
     */
    event SetAllowedTo(address indexed to, bool isAllowedTo);

    /**
     * @notice Mapping of addresses that are allowed to transfer tokens
     * @dev This is used to allow certain addresses to transfer tokens without pausing the token
     */
    mapping(address sender => bool allowed) public isAllowedFrom;

    /**
     * @notice Mapping of addresses that are allowed to receive tokens
     * @dev This is used to allow certain addresses to receive tokens without pausing the token
     */
    mapping(address receiver => bool allowed) public isAllowedTo;

    /**
     * @notice Constructor for the PUFI token
     * totalSupply is 1 billion PUFI
     */
    constructor(address initialOwner) ERC20("PUFFER", "PUFFER") ERC20Permit("PUFFER") Ownable(initialOwner) {
        _mint(initialOwner, 1_000_000_000 ether);
        _setAllowedFrom(initialOwner, true);
        _pause();
    }

    /**
     * @inheritdoc Votes
     */
    function clock() public view virtual override returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @inheritdoc Votes
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @inheritdoc ERC20Permit
     */
    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @notice Unpauses the token
     * @dev Only the owner can unpause the token
     */
    function unpause() external virtual onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the allowedTo status of an address
     * @param receiver The address to set the allowedTo status of
     * @param allowed Whether the address is allowed to receive tokens
     */
    function setAllowedTo(address receiver, bool allowed) external onlyOwner {
        isAllowedTo[receiver] = allowed;
        emit SetAllowedTo(receiver, allowed);
    }

    /**
     * @notice Sets the allowedFrom status of an address
     * @param transferrer The address to set the allowedFrom status of
     * @param allowed Whether the address is allowed to transfer tokens
     */
    function setAllowedFrom(address transferrer, bool allowed) external onlyOwner {
        _setAllowedFrom(transferrer, allowed);
    }

    function _setAllowedFrom(address transferrer, bool allowed) internal {
        isAllowedFrom[transferrer] = allowed;
        emit SetAllowedFrom(transferrer, allowed);
    }

    /**
     * @notice Overrides the _update function to prevent token transfers
     * @dev We override the _update function to act like `_beforeTokenTransfer` hook
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        if (paused()) {
            require(isAllowedFrom[from] || isAllowedTo[to], TransferPaused());
        }

        super._update(from, to, value);
    }
}
