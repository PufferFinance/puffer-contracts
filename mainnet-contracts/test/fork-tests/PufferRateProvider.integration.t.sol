// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { BalancerRateProvider } from "../../src/integrations/BalancerRateProvider.sol";

contract BalancerRateProviderTest is Test {
    BalancerRateProvider rateProvider;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19469193);
        rateProvider = new BalancerRateProvider();
    }

    function test_rate_provider() public view {
        uint256 rate = rateProvider.getRate();

        // 1 wstETH = 1160860144676336301 wei stETH
        // 1 pufETH = 1004594995329975058 wei stETH
        // 1e18 * 1160860144676336301 / 1004594995329975058 = 1155550396003150993

        assertEq(rate, 1155550396003150993, "wstETH is worth more than pufETH");
    }
}
