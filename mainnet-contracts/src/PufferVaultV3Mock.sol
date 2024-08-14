// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20Mock } from "mainnet-contracts/test/mocks/ERC20Mock.sol";

contract PufferVaultV3Mock is ERC20Mock {
    uint256 public totalRewardMintAmount;

    constructor() ERC20Mock("VaultMock", "pufETH") { }

    function mintRewards(uint256 rewardsAmount) external returns (uint256 ethToPufETHRate, uint256 pufETHAmount) {
        _mint(msg.sender, rewardsAmount);
        totalRewardMintAmount += rewardsAmount;
        return (1 ether, rewardsAmount);
    }

    function revertMintRewards(uint256 pufETHAmount, uint256 ethAmount) external {
        totalRewardMintAmount -= ethAmount;
        _burn(msg.sender, pufETHAmount);
    }
}
