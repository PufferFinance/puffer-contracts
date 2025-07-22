// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IPufferVaultV5 } from "src/interface/IPufferVaultV5.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { InvalidAddress } from "src/Errors.sol";
import { PufferVaultV5Liq } from "../mocks/PufferVaultV5Liq.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { LidoWithdrawalQueueMock } from "../mocks/LidoWithdrawalQueueMock.sol";

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
        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(0);
        vm.stopPrank();
        _;
    }

    modifier with1ExitFeeAnd2TreasuryExitFee() {
        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(100);
        pufferVault.setTreasuryExitFeeBasisPoints(200, treasury);
        vm.stopPrank();
        assertEq(pufferVault.getTotalExitFeeBasisPoints(), 300, "totalExitFeeBasisPoints should be 300");
        _;
    }

    modifier withZeroExitFeeAnd2TreasuryExitFee() {
        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(0);
        pufferVault.setTreasuryExitFeeBasisPoints(200, treasury);
        vm.stopPrank();
        assertEq(pufferVault.getTotalExitFeeBasisPoints(), 200, "totalExitFeeBasisPoints should be 200");
        _;
    }

    function test_setExitFeeBasisPoints() public withZeroExitFeeBasisPoints {
        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(100);
        vm.stopPrank();
    }

    function test_setExitFeeBasisPoints_invalid_value() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferVaultV5.InvalidExitFeeBasisPoints.selector);
        pufferVault.setExitFeeBasisPoints(10000);
        vm.stopPrank();
    }

    function test_setTreasuryExitFeeBasisPoints() public {
        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferVaultV5.TreasuryExitFeeBasisPointsSet(0, 100, address(0), treasury);
        pufferVault.setTreasuryExitFeeBasisPoints(100, treasury);
        vm.stopPrank();

        assertEq(pufferVault.getTreasuryExitFeeBasisPoints(), 100, "treasuryExitFeeBasisPoints should be set");
        assertEq(pufferVault.getTreasury(), treasury, "treasury should be set");
    }

    function test_setTreasuryExitFeeBasisPoints_invalid_value() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferVaultV5.InvalidExitFeeBasisPoints.selector);
        pufferVault.setTreasuryExitFeeBasisPoints(10000, treasury);
        vm.stopPrank();
    }

    function test_setTreasuryExitFeeBasisPoints_invalid_address() public {
        vm.startPrank(DAO);
        vm.expectRevert(InvalidAddress.selector);
        pufferVault.setTreasuryExitFeeBasisPoints(100, address(0));
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
        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(exitFeeBasisPoints);
        pufferVault.setTreasuryExitFeeBasisPoints(uint96(treasuryExitFeeBasisPoints), treasury);
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
        uint256 pufEthAmount = pufferVault.convertToShares(userDeposit);
        assertEq(pufEthAmount, aliceBalance, "pufEthAmount should be equal to user's balance");
        assertEq(pufferVault.maxRedeem(alice), aliceBalance, "maxRedeem should be equal to user's balance");

        assertEq(pufEthAmount, 1 ether, "pufEthAmount should be 1 ether");

        uint256 expectedPreviewRedeem = 97 * userDeposit / 100;
        uint256 expectedTreasuryFee = pufferVault.getTreasuryExitFeeBasisPoints() * userDeposit / 100_00;

        assertApproxEqRel(
            pufferVault.previewRedeem(aliceBalance),
            expectedPreviewRedeem,
            pointZeroZeroOne,
            "previewRedeem should be 3% lower"
        );
        assertApproxEqRel(
            pufferVault.maxWithdraw(alice), expectedPreviewRedeem, pointZeroZeroOne, "maxWithdraw should be 3% lower"
        );
        vm.prank(alice);
        uint256 assets = pufferVault.redeem(aliceBalance, alice, alice);

        assertEq(assets, expectedPreviewRedeem, "assets should be equal to expectedPreviewRedeem");
        assertApproxEqRel(
            weth.balanceOf(treasury), expectedTreasuryFee, pointZeroZeroOne, "treasury should have 2% of the deposit"
        );

        // Check exchange rate has now changed
        assertGt(pufferVault.convertToAssets(1 ether), 1 ether, "exchange rate should be higher");
    }

    function test_withdraw_with1ExitFeeAnd2TreasuryExitFee() public with1ExitFeeAnd2TreasuryExitFee {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 pufEthAmount = pufferVault.convertToShares(userDeposit);
        assertEq(pufEthAmount, aliceBalance, "pufEthAmount should be equal to user's balance");
        assertEq(pufferVault.maxRedeem(alice), aliceBalance, "maxRedeem should be equal to user's balance");

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

        // Check exchange rate has now changed
        assertGt(pufferVault.convertToAssets(1 ether), 1 ether, "exchange rate should be higher");
    }

    // Double exchange rate

    function test_redeem_with1ExitFeeAnd2TreasuryExitFeeDiffExchangeRate() public with1ExitFeeAnd2TreasuryExitFee {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        vm.deal(address(pufferVault), address(pufferVault).balance * 2);

        uint256 exchangeRate = pufferVault.convertToAssets(1 ether);

        assertApproxEqRel(exchangeRate, 2 ether, pointZeroZeroOne, "exchange rate should be 2 ether");

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 expectedAssets = exchangeRate * userDeposit / 1 ether;
        uint256 actualAssets = pufferVault.convertToAssets(aliceBalance);
        assertApproxEqRel(
            actualAssets, expectedAssets, pointZeroZeroOne, "actualAssets should be equal to expectedAssets"
        );
        assertEq(pufferVault.maxRedeem(alice), aliceBalance, "maxRedeem should be equal to user's balance");

        uint256 expectedPreviewRedeem = 97 * expectedAssets / 100;
        uint256 expectedTreasuryFee = pufferVault.getTreasuryExitFeeBasisPoints() * expectedAssets / 100_00;

        assertApproxEqRel(
            pufferVault.previewRedeem(aliceBalance),
            expectedPreviewRedeem,
            pointZeroZeroOne,
            "previewRedeem should be 3% lower"
        );
        assertApproxEqRel(
            pufferVault.maxWithdraw(alice), expectedPreviewRedeem, pointZeroZeroOne, "maxWithdraw should be 3% lower"
        );

        vm.prank(alice);
        uint256 assets = pufferVault.redeem(aliceBalance, alice, alice);

        assertEq(assets, expectedPreviewRedeem, "assets should be equal to expectedPreviewRedeem");
        assertApproxEqRel(
            weth.balanceOf(treasury), expectedTreasuryFee, pointZeroZeroOne, "treasury should have 2% of the deposit"
        );

        // Check exchange rate has now changed
        assertGt(pufferVault.convertToAssets(1 ether), exchangeRate, "exchange rate should be higher");
    }

    function test_withdraw_with1ExitFeeAnd2TreasuryExitFeeDiffExchangeRate() public with1ExitFeeAnd2TreasuryExitFee {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        vm.deal(address(pufferVault), address(pufferVault).balance * 2);

        uint256 exchangeRate = pufferVault.convertToAssets(1 ether);

        assertApproxEqRel(exchangeRate, 2 ether, pointZeroZeroOne, "exchange rate should be 2 ether");

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 expectedAssets = exchangeRate * userDeposit / 1 ether;
        uint256 actualAssets = pufferVault.convertToAssets(aliceBalance);
        assertApproxEqRel(
            actualAssets, expectedAssets, pointZeroZeroOne, "actualAssets should be equal to expectedAssets"
        );
        assertEq(pufferVault.maxRedeem(alice), aliceBalance, "maxRedeem should be equal to user's balance");

        uint256 maxWithdraw = pufferVault.maxWithdraw(alice);
        uint256 expectedMaxWithdraw = 97 * expectedAssets / 100;
        uint256 expectedTreasuryFee = pufferVault.getTreasuryExitFeeBasisPoints() * expectedAssets / 100_00;

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

        // Check exchange rate has now changed
        assertGt(pufferVault.convertToAssets(1 ether), exchangeRate, "exchange rate should be higher");
    }

    // Check flows without any fee

    function test_redeem_without_fee() public withZeroExitFeeBasisPoints {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.prank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 expectedAssets = pufferVault.convertToAssets(aliceBalance);
        assertEq(expectedAssets, userDeposit, "expectedAssets should be equal to user's deposit");

        uint256 expectedPreviewRedeem = userDeposit;
        uint256 expectedTreasuryFee = 0;

        assertApproxEqRel(
            pufferVault.previewRedeem(aliceBalance),
            expectedPreviewRedeem,
            pointZeroZeroOne,
            "previewRedeem should be equal to user's deposit"
        );
        assertApproxEqRel(
            pufferVault.maxWithdraw(alice),
            expectedPreviewRedeem,
            pointZeroZeroOne,
            "maxWithdraw should be equal to user's deposit"
        );

        vm.prank(alice);
        uint256 assets = pufferVault.redeem(aliceBalance, alice, alice);

        assertEq(assets, expectedPreviewRedeem, "assets should be equal to expectedPreviewRedeem");
        assertEq(weth.balanceOf(treasury), expectedTreasuryFee, "treasury should have 0 balance");

        // Check exchange rate has not changed
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "exchange rate should be the same");

        // Check alice's balance has not changed
        assertEq(weth.balanceOf(alice), userDeposit, "alice's balance should be the same");
        assertEq(pufferVault.balanceOf(alice), 0, "alice's balance should be 0");
    }

    function test_withdraw_without_fee() public withZeroExitFeeBasisPoints {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.prank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 expectedAssets = pufferVault.convertToAssets(aliceBalance);
        assertEq(expectedAssets, userDeposit, "expectedAssets should be equal to user's deposit");

        uint256 expectedPreviewWithdraw = aliceBalance;
        uint256 expectedTreasuryFee = 0;

        assertApproxEqRel(
            pufferVault.previewWithdraw(aliceBalance),
            expectedPreviewWithdraw,
            pointZeroZeroOne,
            "previewWithdraw should be equal to user's balance"
        );
        assertApproxEqRel(
            pufferVault.maxWithdraw(alice),
            expectedPreviewWithdraw,
            pointZeroZeroOne,
            "maxWithdraw should be equal to user's balance"
        );

        vm.prank(alice);
        uint256 shares = pufferVault.withdraw(aliceBalance, alice, alice);

        assertEq(shares, expectedPreviewWithdraw, "shares should be equal to expectedPreviewWithdraw");
        assertEq(weth.balanceOf(treasury), expectedTreasuryFee, "treasury should have 0 balance");

        // Check exchange rate has not changed
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "exchange rate should be the same");

        // Check alice's balance has not changed
        assertEq(weth.balanceOf(alice), userDeposit, "alice's balance should be the same");
        assertEq(pufferVault.balanceOf(alice), 0, "alice's balance should be 0");
    }

    // Only exitFee (1%)

    function test_redeem_with1ExitFee() public {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 pufEthAmount = pufferVault.convertToShares(userDeposit);
        assertEq(pufEthAmount, aliceBalance, "pufEthAmount should be equal to user's balance");
        assertEq(pufferVault.maxRedeem(alice), aliceBalance, "maxRedeem should be equal to user's balance");

        assertEq(pufEthAmount, 1 ether, "pufEthAmount should be 1 ether");

        uint256 expectedPreviewRedeem = 99 * userDeposit / 100;

        assertApproxEqRel(
            pufferVault.previewRedeem(aliceBalance),
            expectedPreviewRedeem,
            pointZeroZeroOne,
            "previewRedeem should be 1% lower"
        );
        assertApproxEqRel(
            pufferVault.maxWithdraw(alice), expectedPreviewRedeem, pointZeroZeroOne, "maxWithdraw should be 1% lower"
        );
        vm.prank(alice);
        uint256 assets = pufferVault.redeem(aliceBalance, alice, alice);

        assertEq(assets, expectedPreviewRedeem, "assets should be equal to expectedPreviewRedeem");
        assertEq(weth.balanceOf(treasury), 0, "treasury should have received 0 WETH");

        // Check exchange rate has now changed
        assertGt(pufferVault.convertToAssets(1 ether), 1 ether, "exchange rate should be higher");
    }

    function test_withdraw_with1ExitFee() public {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 pufEthAmount = pufferVault.convertToShares(userDeposit);
        assertEq(pufEthAmount, aliceBalance, "pufEthAmount should be equal to user's balance");
        assertEq(pufferVault.maxRedeem(alice), aliceBalance, "maxRedeem should be equal to user's balance");

        assertEq(pufEthAmount, 1 ether, "pufEthAmount should be 1 ether");

        uint256 maxWithdraw = pufferVault.maxWithdraw(alice);

        // Expected 1% less due to fees
        uint256 expectedMaxWithdraw = 99 * userDeposit / 100;

        assertApproxEqRel(maxWithdraw, expectedMaxWithdraw, pointZeroZeroOne, "maxWithdraw should be 1% lower");

        uint256 expectedShares = pufferVault.previewWithdraw(maxWithdraw);

        vm.prank(alice);
        uint256 shares = pufferVault.withdraw(maxWithdraw, alice, alice);

        assertEq(shares, expectedShares, "shares should be equal to expectedShares");
        assertApproxEqRel(
            weth.balanceOf(alice), expectedMaxWithdraw, pointZeroZeroOne, "alice should have 1% less than deposited"
        );
        assertEq(pufferVault.balanceOf(alice), 0, "alice's balance should be 0");

        assertEq(weth.balanceOf(treasury), 0, "treasury should have received 0 WETH");

        // Check exchange rate has now changed
        assertGt(pufferVault.convertToAssets(1 ether), 1 ether, "exchange rate should be higher");
    }

    // Only treasuryExitFee (2%)

    function test_redeem2TreasuryExitFee() public withZeroExitFeeAnd2TreasuryExitFee {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 pufEthAmount = pufferVault.convertToShares(userDeposit);
        assertEq(pufEthAmount, aliceBalance, "pufEthAmount should be equal to user's balance");
        assertEq(pufferVault.maxRedeem(alice), aliceBalance, "maxRedeem should be equal to user's balance");

        assertEq(pufEthAmount, 1 ether, "pufEthAmount should be 1 ether");

        uint256 expectedPreviewRedeem = 98 * userDeposit / 100;
        uint256 expectedTreasuryFee = pufferVault.getTreasuryExitFeeBasisPoints() * userDeposit / 100_00;

        assertApproxEqRel(
            pufferVault.previewRedeem(aliceBalance),
            expectedPreviewRedeem,
            pointZeroZeroOne,
            "previewRedeem should be 2% lower"
        );
        assertApproxEqRel(
            pufferVault.maxWithdraw(alice), expectedPreviewRedeem, pointZeroZeroOne, "maxWithdraw should be 2% lower"
        );
        vm.prank(alice);
        uint256 assets = pufferVault.redeem(aliceBalance, alice, alice);

        assertEq(assets, expectedPreviewRedeem, "assets should be equal to expectedPreviewRedeem");
        assertApproxEqRel(
            weth.balanceOf(treasury), expectedTreasuryFee, pointZeroZeroOne, "treasury should have 2% of the deposit"
        );

        // Check exchange rate has not changed
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "exchange rate should be the same");
    }

    function test_withdraw2TreasuryExitFee() public withZeroExitFeeAnd2TreasuryExitFee {
        uint256 userDeposit = 1 ether;
        // User deposits
        vm.deal(alice, userDeposit);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: userDeposit }(alice);
        vm.stopPrank();

        uint256 aliceBalance = pufferVault.balanceOf(alice);
        uint256 pufEthAmount = pufferVault.convertToShares(userDeposit);
        assertEq(pufEthAmount, aliceBalance, "pufEthAmount should be equal to user's balance");
        assertEq(pufferVault.maxRedeem(alice), aliceBalance, "maxRedeem should be equal to user's balance");

        assertEq(pufEthAmount, 1 ether, "pufEthAmount should be 1 ether");

        uint256 maxWithdraw = pufferVault.maxWithdraw(alice);

        // Expected 2% less due to fees
        uint256 expectedMaxWithdraw = 98 * userDeposit / 100;
        uint256 expectedTreasuryFee = pufferVault.getTreasuryExitFeeBasisPoints() * userDeposit / 100_00;

        assertApproxEqRel(maxWithdraw, expectedMaxWithdraw, pointZeroZeroOne, "maxWithdraw should be 2% lower");

        uint256 expectedShares = pufferVault.previewWithdraw(maxWithdraw);

        vm.prank(alice);
        uint256 shares = pufferVault.withdraw(maxWithdraw, alice, alice);

        assertEq(shares, expectedShares, "shares should be equal to expectedShares");
        assertApproxEqRel(
            weth.balanceOf(alice), expectedMaxWithdraw, pointZeroZeroOne, "alice should have 2% less than deposited"
        );
        assertEq(pufferVault.balanceOf(alice), 0, "alice's balance should be 0");

        assertApproxEqRel(
            weth.balanceOf(treasury), expectedTreasuryFee, pointZeroZeroOne, "treasury should have 2% of the deposit"
        );

        // Check exchange rate has not changed
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "exchange rate should be the same");
    }

    function testFuzz_withdraw_redeem_fee(uint256 aliceDeposit, uint256 bobDeposit, uint256 vaultEthBalance) public {
        // Bound the inputs to reasonable values
        aliceDeposit = bound(aliceDeposit, 0.1 ether, 100 ether);
        bobDeposit = bound(bobDeposit, 0.1 ether, 100 ether);
        vaultEthBalance = bound(vaultEthBalance, 1 ether, 1000 ether);

        address[] memory adds = new address[](5);
        adds[0] = alice;
        adds[1] = bob;
        adds[2] = address(pufferVault);
        adds[3] = treasury;
        adds[4] = LIQUIDITY_PROVIDER;

        _resetAll(adds);

        assertEq(pufferVault.totalAssets(), 0, "Total assets should be 0");
        assertEq(pufferVault.totalSupply(), 0, "Total supply should be 0");

        // Alice and Bob get some ETH
        vm.deal(alice, aliceDeposit);
        vm.deal(bob, bobDeposit);

        // We set vault ETH balance
        vm.deal(address(pufferVault), vaultEthBalance);

        // Alice deposits
        vm.prank(alice);
        pufferVault.depositETH{ value: aliceDeposit }(alice);

        // Bob deposits
        vm.prank(bob);
        pufferVault.depositETH{ value: bobDeposit }(bob);

        uint256 maxWithdraw = pufferVault.maxWithdraw(alice); // Max assets alice can withdraw
        uint256 maxRedeem = pufferVault.maxRedeem(alice); // Max shares alice can redeem
        uint256 prevWithdraw = pufferVault.previewWithdraw(maxWithdraw); // Shares redeemed to withdraw `maxWithdraw` assets
        uint256 prevRedeem = pufferVault.previewRedeem(maxRedeem); // Assets withdrawn by redeeming `maxRedeem` shares

        assertApproxEqAbs(prevWithdraw, maxRedeem, 1, "previewWithdraw and maxRedeem should be equal");
        assertApproxEqAbs(prevRedeem, maxWithdraw, 1, "previewRedeem and maxWithdraw should be equal");

        // Alice withdraws max qty and we save the amount received
        vm.prank(alice);
        uint256 sharesBurned = pufferVault.withdraw(maxWithdraw, alice, alice);
        uint256 aliceBalance = weth.balanceOf(alice);
        uint256 treasuryFee = weth.balanceOf(treasury);
        uint256 exchangeRate = pufferVault.convertToShares(1 ether);

        assertEq(aliceBalance, maxWithdraw, "maxWithdraw should be eq to ethReceived from withdraw");
        assertEq(sharesBurned, maxRedeem, "maxRedeem should be eq to shared burned in withdraw");

        // Reset state

        _resetAll(adds);

        assertEq(pufferVault.totalAssets(), 0, "Total assets should be 0");
        assertEq(pufferVault.totalSupply(), 0, "Total supply should be 0");

        // Alice and Bob get some ETH
        vm.deal(alice, aliceDeposit);
        vm.deal(bob, bobDeposit);

        // We set vault ETH balance
        deal(address(pufferVault), vaultEthBalance);

        // Alice deposits
        vm.prank(alice);
        pufferVault.depositETH{ value: aliceDeposit }(alice);

        // Bob deposits
        vm.prank(bob);
        pufferVault.depositETH{ value: bobDeposit }(bob);

        // Alice redeems
        vm.prank(alice);
        uint256 aliceRedeem = pufferVault.redeem(maxRedeem, alice, alice);
        uint256 aliceBalance2 = weth.balanceOf(alice);
        uint256 treasuryFee2 = weth.balanceOf(treasury);
        uint256 exchangeRate2 = pufferVault.convertToShares(1 ether);

        assertEq(aliceRedeem, aliceBalance2, "Alice gets weth in same amount as redeem func returns");

        assertApproxEqAbs(aliceBalance2, aliceBalance, 1, "Alice should get the same from withdraw and redeem");
        assertApproxEqAbs(sharesBurned, maxRedeem, 1, "Alice should burn the same shares from withdraw and redeem");

        assertApproxEqAbs(treasuryFee, treasuryFee2, 1, "Treasury gets the same fee");

        assertEq(exchangeRate, exchangeRate2, "Vault exchange rate remains identical with withdraw or redeem");
    }

    function testFuzz_withdraw_redeem_treasury_fee(uint256 aliceDeposit, uint256 bobDeposit, uint256 vaultEthBalance)
        public
        with1ExitFeeAnd2TreasuryExitFee
    {
        testFuzz_withdraw_redeem_fee(aliceDeposit, bobDeposit, vaultEthBalance);
    }

    function testFuzz_withdraw_redeem_treasury_fuzzy_fee(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 vaultEthBalance,
        uint256 exitFee,
        uint256 treasuryFee
    ) public {
        exitFee = bound(exitFee, 0, 2_50);
        treasuryFee = bound(treasuryFee, 0, 2_50);
        uint96 actualTreasuryFee = uint96(treasuryFee);
        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(exitFee);
        pufferVault.setTreasuryExitFeeBasisPoints(actualTreasuryFee, treasury);
        vm.stopPrank();

        testFuzz_withdraw_redeem_fee(aliceDeposit, bobDeposit, vaultEthBalance);
    }

    function testFuzz_redeem_previewRedeem(uint256 aliceDeposit, uint256 bobDeposit, uint256 vaultEthBalance) public {
        // Bound the inputs to reasonable values
        aliceDeposit = bound(aliceDeposit, 0.1 ether, 100 ether);
        bobDeposit = bound(bobDeposit, 0.1 ether, 100 ether);
        vaultEthBalance = bound(vaultEthBalance, 1 ether, 1000 ether);

        address[] memory adds = new address[](5);
        adds[0] = alice;
        adds[1] = bob;
        adds[2] = address(pufferVault);
        adds[3] = treasury;
        adds[4] = LIQUIDITY_PROVIDER;

        _resetAll(adds);

        assertEq(pufferVault.totalAssets(), 0, "Total assets should be 0");
        assertEq(pufferVault.totalSupply(), 0, "Total supply should be 0");

        // Alice and Bob get some ETH
        vm.deal(alice, aliceDeposit);
        vm.deal(bob, bobDeposit);

        // We set vault ETH balance
        vm.deal(address(pufferVault), vaultEthBalance);

        // Alice deposits
        vm.prank(alice);
        pufferVault.depositETH{ value: aliceDeposit }(alice);

        // Bob deposits
        vm.prank(bob);
        pufferVault.depositETH{ value: bobDeposit }(bob);

        uint256 alicePufEthBalace = pufferVault.balanceOf(alice);

        uint256 sharesToRedeem;
        sharesToRedeem = bound(sharesToRedeem, 0, alicePufEthBalace);

        uint256 assetsPreviewRedeem = pufferVault.previewRedeem(sharesToRedeem);

        vm.prank(alice);
        uint256 assetsRedeem = pufferVault.redeem(sharesToRedeem, alice, alice);

        assertEq(assetsRedeem, assetsPreviewRedeem, "redeem and previewRedeem should return the same amount of assets");
    }

    function testFuzz_redeem_previewRedeem_treasury_fee(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 vaultEthBalance
    ) public with1ExitFeeAnd2TreasuryExitFee {
        testFuzz_redeem_previewRedeem(aliceDeposit, bobDeposit, vaultEthBalance);
    }

    function testFuzz_redeem_previewRedeem_treasury_fuzzy_fee(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 vaultEthBalance,
        uint256 exitFee,
        uint256 treasuryFee
    ) public {
        exitFee = bound(exitFee, 0, 2_50);
        treasuryFee = bound(treasuryFee, 0, 2_50);
        uint96 actualTreasuryFee = uint96(treasuryFee);
        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(exitFee);
        pufferVault.setTreasuryExitFeeBasisPoints(actualTreasuryFee, treasury);
        vm.stopPrank();

        testFuzz_redeem_previewRedeem(aliceDeposit, bobDeposit, vaultEthBalance);
    }

    function test_maxRedeem_liquidity() public with1ExitFeeAnd2TreasuryExitFee {
        _upgradeToLiqMock();

        address[] memory adds = new address[](5);
        adds[0] = alice;
        adds[1] = bob;
        adds[2] = address(pufferVault);
        adds[3] = treasury;
        adds[4] = LIQUIDITY_PROVIDER;

        _resetAll(adds);

        assertEq(pufferVault.totalAssets(), 0, "Total assets should be 0");
        assertEq(pufferVault.totalSupply(), 0, "Total supply should be 0");

        uint256 aliceDeposit = 1 ether;

        deal(alice, aliceDeposit);

        // Alice deposits
        vm.startPrank(alice);
        pufferVault.depositETH{ value: aliceDeposit }(alice);

        PufferVaultV5Liq(payable(address(pufferVault))).reduceLiquidity(0.5 ether);

        uint256 availableLiquidity = weth.balanceOf(address(pufferVault)) + address(pufferVault).balance;

        assertEq(availableLiquidity, 0.5 ether, "balance is 0.5 ether");

        uint256 maxRedeem = pufferVault.maxRedeem(alice);
        uint256 maxWithdraw = pufferVault.maxWithdraw(alice);
        uint256 previewRedeem = pufferVault.previewRedeem(maxRedeem);

        uint256 assetsWithdrawn = pufferVault.redeem(maxRedeem, alice, alice);
        assertEq(maxWithdraw, assetsWithdrawn, "maxWithdraw should be the same as assetsWithdrawn");
        assertEq(previewRedeem, assetsWithdrawn, "previewRedeem should be the same as assetsWithdrawn");
    }

    function testFuzz_maxRedeem_liquidity(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 vaultEthBalance,
        uint256 exitFee,
        uint256 treasuryFee
    ) public with1ExitFeeAnd2TreasuryExitFee {
        aliceDeposit = bound(aliceDeposit, 0.1 ether, 100 ether);
        bobDeposit = bound(bobDeposit, 0.1 ether, 100 ether);
        vaultEthBalance = bound(vaultEthBalance, 0.1 ether, 5 ether);
        exitFee = bound(exitFee, 0, 2_50);
        treasuryFee = bound(treasuryFee, 0, 2_50);

        uint96 actualTreasuryFee = uint96(treasuryFee);
        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(exitFee);
        pufferVault.setTreasuryExitFeeBasisPoints(actualTreasuryFee, treasury);
        vm.stopPrank();

        _upgradeToLiqMock();

        address[] memory adds = new address[](5);
        adds[0] = alice;
        adds[1] = bob;
        adds[2] = address(pufferVault);
        adds[3] = treasury;
        adds[4] = LIQUIDITY_PROVIDER;

        _resetAll(adds);

        assertEq(pufferVault.totalAssets(), 0, "Total assets should be 0");
        assertEq(pufferVault.totalSupply(), 0, "Total supply should be 0");

        // We set vault ETH balance
        vm.deal(address(pufferVault), vaultEthBalance);

        deal(alice, aliceDeposit);

        // Alice deposits
        vm.startPrank(alice);
        pufferVault.depositETH{ value: aliceDeposit }(alice);

        uint256 lockedLiquidity;
        lockedLiquidity = bound(lockedLiquidity, 0, vaultEthBalance + aliceDeposit);

        PufferVaultV5Liq(payable(address(pufferVault))).reduceLiquidity(lockedLiquidity);

        uint256 maxRedeem = pufferVault.maxRedeem(alice);
        uint256 maxWithdraw = pufferVault.maxWithdraw(alice);
        uint256 previewRedeem = pufferVault.previewRedeem(maxRedeem);

        uint256 assetsWithdrawn = pufferVault.redeem(maxRedeem, alice, alice);

        assertApproxEqAbs(maxWithdraw, assetsWithdrawn, 1, "maxWithdraw should be the same as assetsWithdrawn");
        assertApproxEqAbs(previewRedeem, assetsWithdrawn, 1, "previewRedeem should be the same as assetsWithdrawn");
    }

    function testFuzz_maxWithdraw_liquidity(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 vaultEthBalance,
        uint256 exitFee,
        uint256 treasuryFee
    ) public with1ExitFeeAnd2TreasuryExitFee {
        aliceDeposit = bound(aliceDeposit, 0.1 ether, 100 ether);
        bobDeposit = bound(bobDeposit, 0.1 ether, 100 ether);
        vaultEthBalance = bound(vaultEthBalance, 0.1 ether, 5 ether);
        exitFee = bound(exitFee, 0, 2_50);
        treasuryFee = bound(treasuryFee, 0, 2_50);

        uint96 actualTreasuryFee = uint96(treasuryFee);
        vm.startPrank(DAO);
        pufferVault.setExitFeeBasisPoints(exitFee);
        pufferVault.setTreasuryExitFeeBasisPoints(actualTreasuryFee, treasury);
        vm.stopPrank();

        _upgradeToLiqMock();

        address[] memory adds = new address[](5);
        adds[0] = alice;
        adds[1] = bob;
        adds[2] = address(pufferVault);
        adds[3] = treasury;
        adds[4] = LIQUIDITY_PROVIDER;

        _resetAll(adds);

        assertEq(pufferVault.totalAssets(), 0, "Total assets should be 0");
        assertEq(pufferVault.totalSupply(), 0, "Total supply should be 0");

        // We set vault ETH balance
        vm.deal(address(pufferVault), vaultEthBalance);

        deal(alice, aliceDeposit);

        // Alice deposits
        vm.startPrank(alice);
        pufferVault.depositETH{ value: aliceDeposit }(alice);

        uint256 lockedLiquidity;
        lockedLiquidity = bound(lockedLiquidity, 0, vaultEthBalance + aliceDeposit);

        PufferVaultV5Liq(payable(address(pufferVault))).reduceLiquidity(lockedLiquidity);

        uint256 maxRedeem = pufferVault.maxRedeem(alice);
        uint256 maxWithdraw = pufferVault.maxWithdraw(alice);
        uint256 previewWithdraw = pufferVault.previewWithdraw(maxWithdraw);

        uint256 sharesRedeemed = pufferVault.withdraw(maxWithdraw, alice, alice);
        assertApproxEqAbs(maxRedeem, sharesRedeemed, 1, "maxRedeem should be the same as sharesRedeemed");
        assertApproxEqAbs(previewWithdraw, sharesRedeemed, 1, "previewWithdraw should be the same as sharesRedeemed");
    }

    function _resetAll(address[] memory users) internal {
        for (uint256 i = 0; i < users.length; i++) {
            deal(users[i], 0);
            deal(address(weth), users[i], 0);
            deal(address(pufferVault), users[i], 0, true);
        }
    }

    function _upgradeToLiqMock() internal {
        // Grant upgrade role to timelock
        uint64 tempRol = 64;
        vm.startPrank(timelock);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UUPSUpgradeable.upgradeToAndCall.selector;
        accessManager.setTargetFunctionRole(address(pufferVault), selectors, tempRol);
        accessManager.grantRole(tempRol, address(timelock), 0);

        PufferVaultV5Liq newImplementation =
            new PufferVaultV5Liq(stETH, weth, new LidoWithdrawalQueueMock(), pufferOracle, revenueDepositor);

        UUPSUpgradeable(address(pufferVault)).upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }
}
