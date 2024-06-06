// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
