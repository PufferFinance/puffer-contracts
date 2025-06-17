// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IPufferVaultV5 } from "src/interface/IPufferVaultV5.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { InvalidAddress } from "src/Errors.sol";
import { console } from "forge-std/console.sol";

contract PufferVaultTest is UnitTestHelper {
    uint256 pointZeroZeroOne = 0.0001e18;

    address treasury = makeAddr("treasury");

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

    modifier with1ExitFeeAnd2TreasuryExitFee() {
        vm.startPrank(address(timelock));
        pufferVault.setExitFeeBasisPoints(100);
        pufferVault.setTreasury(treasury);
        pufferVault.setTreasuryExitFeeBasisPoints(200);
        vm.stopPrank();
        assertEq(pufferVault.getTotalExitFeeBasisPoints(), 300, "totalExitFeeBasisPoints should be 300");
        _;
    }

    function test_setTreasury() public {
        vm.startPrank(address(timelock));
        pufferVault.setTreasury(treasury);
        vm.stopPrank();

        assertEq(pufferVault.getTreasury(), address(treasury), "treasury should be set");
    }

    function test_setTreasury_invalid_address() public {
        vm.startPrank(address(timelock));
        vm.expectRevert(InvalidAddress.selector);
        pufferVault.setTreasury(address(0));
        vm.stopPrank();
    }

    function test_setExitFeeBasisPoints() public withZeroExitFeeBasisPoints {
        vm.startPrank(address(timelock));
        pufferVault.setExitFeeBasisPoints(100);
        vm.stopPrank();
    }

    function test_setExitFeeBasisPoints_invalid_value() public {
        vm.startPrank(address(timelock));
        vm.expectRevert(IPufferVaultV5.InvalidExitFeeBasisPoints.selector);
        pufferVault.setExitFeeBasisPoints(10000);
        vm.stopPrank();
    }

    function test_setTreasuryExitFeeBasisPoints() public {
        vm.startPrank(address(timelock));
        pufferVault.setTreasury(treasury);
        pufferVault.setTreasuryExitFeeBasisPoints(100);
        vm.stopPrank();

        assertEq(pufferVault.getTreasuryExitFeeBasisPoints(), 100, "treasuryExitFeeBasisPoints should be set");
    }

    function test_setTreasuryExitFeeBasisPoints_invalid_value() public {
        vm.startPrank(address(timelock));
        vm.expectRevert(IPufferVaultV5.InvalidExitFeeBasisPoints.selector);
        pufferVault.setTreasuryExitFeeBasisPoints(10000);
        vm.stopPrank();
    }

    function test_setTreasuryExitFeeBasisPoints_invalid_address() public {
        vm.startPrank(address(timelock));
        vm.expectRevert(InvalidAddress.selector);
        pufferVault.setTreasuryExitFeeBasisPoints(100);
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

    function testFuzz_maxWithdrawRedeem(
        uint256 userDeposit,
        uint256 vaultLiquidity,
        uint256 exitFeeBasisPoints,
        uint256 treasuryExitFeeBasisPoints
    ) public {
        // Bound inputs to reasonable ranges
        userDeposit = bound(userDeposit, 0.1 ether, 1000 ether);
        vaultLiquidity = bound(vaultLiquidity, 0.1 ether, 1000 ether);
        exitFeeBasisPoints = bound(exitFeeBasisPoints, 0, 200); // Max 2% fee
        treasuryExitFeeBasisPoints = bound(treasuryExitFeeBasisPoints, 0, 200); // Max 2% fee
        // Set exit fee
        vm.startPrank(address(timelock));
        pufferVault.setExitFeeBasisPoints(exitFeeBasisPoints);
        pufferVault.setTreasury(treasury);
        pufferVault.setTreasuryExitFeeBasisPoints(treasuryExitFeeBasisPoints);
        vm.stopPrank();

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

    // Tests with 1% exit fee and 2% treasury exit fee

    function test_redeem_with1ExitFeeAnd2TreasuryExitFee() public with1ExitFeeAnd2TreasuryExitFee {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 pufEthAmount = pufferVault.convertToAssets(userDeposit);
        assertEq(pufEthAmount, aliceBalance, "pufEthAmount should be equal to user's balance");

        assertEq(pufEthAmount, 1 ether, "pufEthAmount should be 1 ether");

        // Expected 3% less due to fees

        // uint256 expectedPreviewRedeem = 100*userDeposit / 103;
        // uint256 expectedFee = userDeposit - expectedPreviewRedeem;

        // assertApproxEqRel(pufferVault.previewRedeem(aliceBalance), expectedPreviewRedeem, pointZeroZeroOne,"previewRedeem should be 3% lower");
        // vm.prank(alice);
        // uint256 assets = pufferVault.redeem(aliceBalance, alice, alice);

        // console.log('assets', assets);
        // console.log('expectedPreviewRedeem', expectedPreviewRedeem);
        // console.log("aliceBalance", aliceBalance);
        // console.log('weth alice balance', weth.balanceOf(alice));
        // console.log('weth treasury balance', weth.balanceOf(treasury));

        // assertEq(pufferVault.balanceOf(alice), 0, "alice's balance should be 0");
        // assertApproxEqRel(weth.balanceOf(treasury), expectedFee*2/3, pointZeroZeroOne, "treasury should have 2% of the deposit");

        uint256 expectedPreviewRedeem = 97 * userDeposit / 100;
        uint256 expectedTreasuryFee = pufferVault.getTreasuryExitFeeBasisPoints() * userDeposit / 100_00;

        assertApproxEqRel(
            pufferVault.previewRedeem(aliceBalance),
            expectedPreviewRedeem,
            pointZeroZeroOne,
            "previewRedeem should be 3% lower"
        );
        vm.prank(alice);
        uint256 assets = pufferVault.redeem(aliceBalance, alice, alice);

        assertEq(assets, expectedPreviewRedeem, "assets should be equal to expectedPreviewRedeem");
        assertApproxEqRel(
            weth.balanceOf(treasury), expectedTreasuryFee, pointZeroZeroOne, "treasury should have 2% of the deposit"
        );
    }

    function test_withdraw_with1ExitFeeAnd2TreasuryExitFee() public with1ExitFeeAnd2TreasuryExitFee {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 pufEthAmount = pufferVault.convertToAssets(userDeposit);
        assertEq(pufEthAmount, aliceBalance, "pufEthAmount should be equal to user's balance");

        assertEq(pufEthAmount, 1 ether, "pufEthAmount should be 1 ether");

        uint256 maxWithdraw = pufferVault.maxWithdraw(alice);

        // Expected 3% less due to fees
        uint256 expectedMaxWithdraw = 97 * userDeposit / 100;
        uint256 expectedTreasuryFee = pufferVault.getTreasuryExitFeeBasisPoints() * userDeposit / 100_00;

        assertApproxEqRel(maxWithdraw, expectedMaxWithdraw, pointZeroZeroOne, "maxWithdraw should be 3% lower");

        uint256 expectedShares = pufferVault.previewWithdraw(maxWithdraw);

        vm.prank(alice);
        uint256 shares = pufferVault.withdraw(maxWithdraw, alice, alice);

        assertEq(shares, expectedShares, "shares should be equal to expectedShares");
        assertApproxEqRel(
            weth.balanceOf(alice), expectedMaxWithdraw, pointZeroZeroOne, "alice should have 3% less than deposited"
        );
        assertEq(pufferVault.balanceOf(alice), 0, "alice's balance should be 0");

        assertApproxEqRel(
            weth.balanceOf(treasury), expectedTreasuryFee, pointZeroZeroOne, "treasury should have 2% of the deposit"
        );
    }
}
