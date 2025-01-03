// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IPufferVaultV2 } from "src/interface/IPufferVaultV2.sol";

contract PufferVaultTest is UnitTestHelper {
    uint256 pointZeroZeroOne = 0.0001e18;

    function test_setup_vault() public view {
        assertEq(pufferVault.asset(), address(weth), "asset should be WETH");
        assertEq(pufferVault.totalSupply(), 1000 ether, "totalSupply should be 1000 ETH");
        assertEq(pufferVault.totalAssets(), 1000 ether, "totalAssets should be 1000 ETH");
        assertEq(pufferVault.getExitFeeBasisPoints(), 100, "fee should be 100");
        assertEq(pufferVault.decimals(), 18, "decimals should be 18");
    }

    modifier withZeroExitFeeBasisPoints() {
        vm.startPrank(address(timelock));
        pufferVault.setExitFeeBasisPoints(0);
        vm.stopPrank();
        _;
    }

    function test_setExitFeeBasisPoints() public withZeroExitFeeBasisPoints {
        vm.startPrank(address(timelock));
        pufferVault.setExitFeeBasisPoints(100);
        vm.stopPrank();
    }

    function test_setExitFeeBasisPoints_invalid_value() public {
        vm.startPrank(address(timelock));
        vm.expectRevert(IPufferVaultV2.InvalidExitFeeBasisPoints.selector);
        pufferVault.setExitFeeBasisPoints(10000);
        vm.stopPrank();
    }

    function test_previewRedeem() public withZeroExitFeeBasisPoints {
        uint256 redeemAmount = pufferVault.previewRedeem(1 ether);
        assertApproxEqRel(redeemAmount, 1 ether, pointZeroZeroOne, "redeemAmount should be 1 ether");
    }

    function test_previewWithdraw() public withZeroExitFeeBasisPoints {
        uint256 withdrawAmount = pufferVault.previewWithdraw(1 ether);
        assertApproxEqRel(withdrawAmount, 1 ether, pointZeroZeroOne, "withdrawAmount should be 1 ether");
    }

    function test_redeem() public withZeroExitFeeBasisPoints {
        vm.deal(alice, 1 ether);

        vm.startPrank(alice);
        pufferVault.approve(address(this), 1 ether);
        pufferVault.depositETH{ value: 1 ether }(alice);

        pufferVault.redeem(1 ether, alice, alice);
        vm.stopPrank();
    }

    function test_mint_vault_v5() public withZeroExitFeeBasisPoints {
        deal(address(weth), alice, 1 ether);

        vm.startPrank(alice);
        weth.approve(address(pufferVault), 1 ether);

        pufferVault.mint(1 ether, alice);
    }
}
