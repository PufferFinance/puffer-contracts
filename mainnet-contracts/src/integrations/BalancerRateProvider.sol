// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

interface IRateProvider {
    function getRate() external view returns (uint256);
}

interface IWstETH {
    function stEthPerToken() external view returns (uint256);
}

interface IPufETH {
    function convertToAssets(uint256 shares) external view returns (uint256);
}

/**
 * @title BalancerRateProvider
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract BalancerRateProvider is IRateProvider {
    /**
     * @notice https://etherscan.io/token/0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0
     */
    IWstETH public constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    /**
     * @notice https://etherscan.io/address/0xD9A442856C234a39a81a089C06451EBAa4306a72
     */
    IPufETH public constant pufETH = IPufETH(0xD9A442856C234a39a81a089C06451EBAa4306a72);

    /**
     * @notice Returns an 18 decimal fixed point number that is the exchange rate of wstETH:pufETH
     */
    function getRate() external view returns (uint256) {
        return 1e18 * wstETH.stEthPerToken() / pufETH.convertToAssets(1 ether);
    }
}
