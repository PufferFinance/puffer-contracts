// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IPufferVaultV2 } from "src/interface/IPufferVaultV2.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

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

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector, alice, 100 ether, 1 ether)
        );
        pufferVault.redeem(100 ether, alice, alice);

        pufferVault.redeem(1 ether, alice, alice);
        vm.stopPrank();
    }

    function test_mint_vault_v5() public withZeroExitFeeBasisPoints {
        deal(address(weth), alice, 1 ether);

        vm.startPrank(alice);
        weth.approve(address(pufferVault), 1 ether);

        pufferVault.mint(1 ether, alice);
    }

    // See mainnet-contracts/test/fork-tests/PufferVaultForkTest.t.sol for real test
    // For some reason code coverage doesn't account for tests in the file above
    function test_initiateETHWithdrawalsFromLidoDummy() public {
        vm.startPrank(OPERATIONS_MULTISIG);

        pufferVault.initiateETHWithdrawalsFromLido(new uint256[](1));

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 1;
        pufferVault.claimWithdrawalsFromLido(requestIds);
    }

    function testFuzz_maxWithdrawRedeem(uint256 userDeposit, uint256 vaultLiquidity, uint256 exitFeeBasisPoints)
        public
    {
        // Bound inputs to reasonable ranges
        userDeposit = bound(userDeposit, 0.1 ether, 1000 ether);
        vaultLiquidity = bound(vaultLiquidity, 0.1 ether, 1000 ether);
        exitFeeBasisPoints = bound(exitFeeBasisPoints, 0, 200); // Max 2% fee

        // Set exit fee
        vm.prank(address(timelock));
        pufferVault.setExitFeeBasisPoints(exitFeeBasisPoints);

        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        // Set vault liquidity
        assertEq(weth.balanceOf(address(pufferVault)), 0, "Vault WETH should be 0");
        vm.deal(address(pufferVault), vaultLiquidity);

        // Get user's potential assets based on shares
        uint256 maxUserAssets = pufferVault.previewRedeem(pufferVault.balanceOf(alice));

        // Test maxWithdraw
        uint256 maxWithdraw = pufferVault.maxWithdraw(alice);
        uint256 expectedMaxWithdraw = maxUserAssets < vaultLiquidity ? maxUserAssets : vaultLiquidity;
        assertEq(maxWithdraw, expectedMaxWithdraw, "maxWithdraw should return min of user assets and vault liquidity");

        // Test maxRedeem
        uint256 maxRedeem = pufferVault.maxRedeem(alice);
        uint256 expectedMaxRedeem = pufferVault.balanceOf(alice) < pufferVault.previewWithdraw(vaultLiquidity)
            ? pufferVault.balanceOf(alice)
            : pufferVault.previewWithdraw(vaultLiquidity);
        assertEq(maxRedeem, expectedMaxRedeem, "maxRedeem should return min of user shares and shares from liquidity");

        // Additional invariant checks
        assertTrue(maxWithdraw <= vaultLiquidity, "maxWithdraw cannot exceed vault liquidity");
        assertTrue(maxRedeem <= pufferVault.balanceOf(alice), "maxRedeem cannot exceed user shares");

        // If user has more shares than vault liquidity
        if (maxUserAssets > vaultLiquidity) {
            assertEq(maxWithdraw, vaultLiquidity, "When liquidity limited, maxWithdraw should equal vault liquidity");
            assertEq(
                maxRedeem,
                pufferVault.previewWithdraw(vaultLiquidity),
                "When liquidity limited, maxRedeem should be shares equivalent to vault liquidity"
            );
        }

        // If user has less shares than vault liquidity
        if (maxUserAssets < vaultLiquidity) {
            assertEq(maxWithdraw, maxUserAssets, "When user limited, maxWithdraw should equal user's assets");
            assertEq(maxRedeem, pufferVault.balanceOf(alice), "When user limited, maxRedeem should equal user's shares");
        }
    }

    function testFuzz_maxWithdrawRedeem_ZeroValues() public {
        // Test with zero liquidity
        vm.deal(address(pufferVault), 0);
        assertEq(pufferVault.maxWithdraw(alice), 0, "maxWithdraw should be 0 with zero liquidity");
        assertEq(pufferVault.maxRedeem(alice), 0, "maxRedeem should be 0 with zero liquidity");

        // Test with zero shares but non-zero liquidity
        vm.deal(address(pufferVault), 1 ether);
        address userWithNoShares = address(0xdead);
        assertEq(pufferVault.maxWithdraw(userWithNoShares), 0, "maxWithdraw should be 0 with zero shares");
        assertEq(pufferVault.maxRedeem(userWithNoShares), 0, "maxRedeem should be 0 with zero shares");
    }
}
