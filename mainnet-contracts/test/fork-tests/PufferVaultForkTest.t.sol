// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { IPufferVault } from "../../src/interface/IPufferVault.sol";
import { IPufferVaultV2 } from "../../src/interface/IPufferVaultV2.sol";
import { IPufferVaultV5 } from "../../src/interface/IPufferVaultV5.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { console } from "forge-std/Test.sol";
import { IStETH } from "../../src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "../../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IPufferOracleV2 } from "../../src/interface/IPufferOracleV2.sol";
import { IPufferRevenueDepositor } from "../../src/interface/IPufferRevenueDepositor.sol";
import { MockPufferOracle } from "../mocks/MockPufferOracle.sol";

/**
 * @notice For some reason the code coverage doesn't consider that this mainnet fork tests increase the code coverage..
 * @notice Added tests for maxWithdraw and maxRedeem V5 functionality.
 */
contract PufferVaultForkTest is MainnetForkTestHelper {
    function setUp() public virtual override { }

    modifier oldFork() {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21378494); // Dec-11-2024 09:52:59 AM +UTC
        _setupLiveContracts();
        _;
    }

    modifier recentFork() {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21549844); // Jan-04-2025 08:13:23 AM +UTC
        _setupLiveContracts();
        _;
    }

    // In this test, we initiate ETH withdrawal from Lido
    function test_initiateETHWithdrawalsFromLido() public recentFork {
        vm.startPrank(_getOPSMultisig());

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        uint256[] memory requestIds = pufferVault.initiateETHWithdrawalsFromLido(amounts);
        requestIds[0] = 66473; // That is the next request id for this test

        vm.expectEmit(true, true, true, true);
        emit IPufferVault.RequestedWithdrawals(requestIds);
        pufferVault.initiateETHWithdrawalsFromLido(amounts);
    }

    // In this test, we claim some queued withdrawal from Lido
    function test_claimETHWithdrawalsFromLido() public oldFork {
        vm.startPrank(_getOPSMultisig());

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 62744; // That is the next request id for this test

        uint256 balanceBefore = address(pufferVault).balance;

        vm.expectEmit(true, true, true, true);
        emit IPufferVault.ClaimedWithdrawals(requestIds);
        pufferVault.claimWithdrawalsFromLido(requestIds);

        uint256 balanceAfter = address(pufferVault).balance;
        assertEq(balanceAfter, balanceBefore + 107.293916980728143835 ether, "Balance should increase by ~107 ether");
    }

    // Prevent deposit and withdraw in the same transaction
    function test_depositAndWithdrawRevertsInTheSameTx() public oldFork {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);

        pufferVault.depositETH{ value: 1 ether }(alice);

        vm.expectRevert(IPufferVaultV2.DepositAndWithdrawalForbidden.selector);
        pufferVault.redeem(1 ether, alice, alice);
    }

    function test_maxWithdraw_ZeroBalance() public recentFork {
        assertEq(((pufferVault)).maxWithdraw(alice), 0, "maxWithdraw zero balance");
    }

    function test_maxRedeem_ZeroBalance() public recentFork {
        assertEq(((pufferVault)).maxRedeem(alice), 0, "maxRedeem zero balance");
    }

    function test_maxWithdrawRedeem_UserLimited() public recentFork {
        IWETH weth = IWETH(_getWETH());
        ERC20 pufETH = ERC20(address(pufferVault)); // Cast to ERC20 to access balanceOf

        // Set exit fee to 1% (100 basis points) for testing
        vm.prank(_getOPSMultisig());
        pufferVault.setExitFeeBasisPoints(100);

        // Ensure vault has ample liquidity for this test
        // We can check the balance, or simply assume it's high at this block
        uint256 vaultWethBalance = weth.balanceOf(address(pufferVault));
        uint256 vaultEthBalance = address(pufferVault).balance;
        uint256 vaultLiquidity = vaultWethBalance + vaultEthBalance;
        console.log("Vault Initial WETH:", vaultWethBalance);
        console.log("Vault Initial ETH:", vaultEthBalance);
        assertTrue(vaultLiquidity > 10 ether, "Vault needs sufficient liquidity for user-limited test");

        // Give user ETH and deposit
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: 1 ether }(alice);
        uint256 aliceShares = pufETH.balanceOf(alice);
        assertTrue(aliceShares > 0, "Alice should have shares");
        vm.stopPrank();

        // Calculate expected max assets Alice can withdraw (this already accounts for fees via previewRedeem)
        uint256 expectedMaxAssets = pufferVault.previewRedeem(aliceShares);
        console.log("Expected max assets (after fees):", expectedMaxAssets);

        // Max withdraw should be limited by Alice's shares (converted to assets, considering fees)
        assertEq(pufferVault.maxWithdraw(alice), expectedMaxAssets, "maxWithdraw user limited");

        // Max redeem should be limited by Alice's shares
        assertEq(pufferVault.maxRedeem(alice), aliceShares, "maxRedeem user limited");
    }

    function test_maxWithdrawRedeem_LiquidityLimited() public recentFork {
        _upgradeToV5();
        IWETH weth = IWETH(_getWETH());

        // Set exit fee to 1% (100 basis points) for testing
        uint256 userDeposit = 50 ether;
        uint256 vaultLiquidity = 1 ether;
        uint256 exitFeeBasisPoints = 100; // 1% fee

        // Set exit fee
        vm.prank(_getOPSMultisig());
        pufferVault.setExitFeeBasisPoints(exitFeeBasisPoints);

        // User deposits 10 ETH
        console.log("bob balance before", pufferVault.balanceOf(bob));
        vm.deal(bob, userDeposit);
        vm.prank(bob);
        pufferVault.depositETH{ value: userDeposit }(bob);
        console.log("bob shares", pufferVault.balanceOf(bob));
        // Simulate limited liquidity by directly setting the vault's balance

        // First, check there is no WETH balance
        assertEq(weth.balanceOf(address(pufferVault)), 0, "Vault WETH should be 0");

        // Then set the vault's ETH balance to the desired liquidity
        vm.deal(address(pufferVault), vaultLiquidity);

        // Calculate expected values
        uint256 userShares = pufferVault.balanceOf(bob);
        uint256 fee = vaultLiquidity * exitFeeBasisPoints / 10000;
        uint256 availableLiquidity = vaultLiquidity - fee;
        console.log("availableLiquidity", availableLiquidity);
        uint256 maxUserAssets = pufferVault.previewRedeem(userShares);
        console.log("maxUserAssets", maxUserAssets);
        // Test maxWithdraw
        assertEq(
            pufferVault.maxWithdraw(bob),
            availableLiquidity,
            "maxWithdraw should be limited by vault liquidity after fees"
        );
        uint256 expectedMaxRedeem = pufferVault.previewWithdraw(vaultLiquidity);
        // Test maxRedeem
        assertEq(
            pufferVault.maxRedeem(bob), expectedMaxRedeem, "maxRedeem should be limited by vault liquidity after fees"
        );
    }

    function test_maxWithdrawRedeem_ZeroLiquidity() public recentFork {
        _upgradeToV5();
        IWETH weth = IWETH(_getWETH());

        // Give user ETH and deposit to ensure they have shares
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        pufferVault.depositETH{ value: 1 ether }(alice);
        assertTrue(pufferVault.balanceOf(alice) > 0, "Alice should have shares");
        vm.stopPrank();

        // Set vault WETH and ETH liquidity to zero
        // Fix: Use the correct approach to set token balances to zero
        vm.deal(address(pufferVault), 0); // Set vault ETH balance to 0
        // For WETH, we need to withdraw all WETH to ETH first
        if (weth.balanceOf(address(pufferVault)) > 0) {
            vm.prank(address(pufferVault));
            weth.withdraw(weth.balanceOf(address(pufferVault)));
        }

        assertEq(weth.balanceOf(address(pufferVault)), 0, "Vault WETH should be 0");
        assertEq(address(pufferVault).balance, 0, "Vault ETH should be 0");

        // Max withdraw and redeem should be 0 with no liquidity
        assertEq(pufferVault.maxWithdraw(alice), 0, "maxWithdraw zero liquidity");
        assertEq(pufferVault.maxRedeem(alice), 0, "maxRedeem zero liquidity");
    }

    function _upgradeToV5() private {
        MockPufferOracle mockOracle = new MockPufferOracle();
        PufferVaultV5 v5Impl = new PufferVaultV5({
            stETH: IStETH(_getStETH()),
            lidoWithdrawalQueue: ILidoWithdrawalQueue(_getLidoWithdrawalQueue()),
            weth: IWETH(_getWETH()),
            pufferOracle: IPufferOracleV2(address(mockOracle)),
            revenueDepositor: IPufferRevenueDepositor(address(0x21660F4681aD5B6039007f7006b5ab0EF9dE7882))
        });
        vm.prank(address(timelock));
        pufferVault.upgradeToAndCall(address(v5Impl), "");
    }
}
