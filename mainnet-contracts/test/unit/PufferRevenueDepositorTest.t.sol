// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IPufferRevenueDepositor } from "src/interface/IPufferRevenueDepositor.sol";
import { InvalidAddress } from "src/Errors.sol";

/**
 * @title PufferRevenueDepositorTest
 * @dev Test contract for PufferRevenueDepositor
 *
 * @dev Run the following command to execute the tests:
 * forge test --mc PufferRevenueDepositorTest -vvvv
 */
contract PufferRevenueDepositorTest is UnitTestHelper {
    /**
     * @dev Modifier to set the rewards distribution window for the test
     */
    modifier withRewardsDistributionWindow(uint24 newRewardsDistributionWindow) {
        vm.startPrank(DAO);
        revenueDepositor.setRewardsDistributionWindow(newRewardsDistributionWindow);
        _;
        vm.stopPrank();
    }

    function test_sanity() public view {
        assertEq(revenueDepositor.getRnoRewardsBps(), 400, "RNO rewards bps should be 400");
        assertEq(revenueDepositor.getTreasuryRewardsBps(), 500, "Treasury rewards bps should be 500");
        assertEq(revenueDepositor.getRestakingOperators().length, 7, "Should have 7 restaking operators");
        assertTrue(revenueDepositor.TREASURY() != address(0), "Treasury should not be 0");
        assertTrue(address(revenueDepositor.WETH()) != address(0), "WETH should not be 0");
        assertTrue(address(revenueDepositor.PUFFER_VAULT()) != address(0), "PufferVault should not be 0");
    }

    function test_setRewardsDistributionWindow() public {
        assertEq(revenueDepositor.getRewardsDistributionWindow(), 0, "Rewards distribution window should be 0");

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferRevenueDepositor.RewardsDistributionWindowChanged(0, 1 days);
        revenueDepositor.setRewardsDistributionWindow(1 days);

        assertEq(
            revenueDepositor.getRewardsDistributionWindow(), 1 days, "Rewards distribution window should be 1 days"
        );
    }

    function testRevert_setRewardsDistributionWindow_InvalidWindow() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferRevenueDepositor.InvalidDistributionWindow.selector);
        revenueDepositor.setRewardsDistributionWindow(15 days);
    }

    function testRevert_setRewardsDistributionWhenAlreadyDepositing() public withRewardsDistributionWindow(1 days) {
        assertEq(block.timestamp, 1, "Timestamp should be 1");
        deal(address(revenueDepositor), 100 ether);

        vm.startPrank(OPERATIONS_MULTISIG);
        revenueDepositor.depositRevenue();

        vm.startPrank(DAO);
        vm.expectRevert(IPufferRevenueDepositor.CannotChangeDistributionWindow.selector);
        revenueDepositor.setRewardsDistributionWindow(1 days);
    }

    function test_smallRewardsAmount() public withRewardsDistributionWindow(1 days) {
        vm.deal(address(revenueDepositor), 1); // 1 wei

        vm.startPrank(OPERATIONS_MULTISIG);

        vm.expectRevert(IPufferRevenueDepositor.NothingToDistribute.selector);
        revenueDepositor.depositRevenue();

        vm.deal(address(revenueDepositor), 20); // 20 wei
        revenueDepositor.depositRevenue();

        // 1 wei went to the treasury
        assertEq(revenueDepositor.getPendingDistributionAmount(), 19, "Pending distribution amount should be 19");

        // After half of the distribution window, the pending distribution amount is half of the total amount
        vm.warp(block.timestamp + 12 hours);

        // 19/2 = 9.5, rounded down to 9
        assertEq(revenueDepositor.getPendingDistributionAmount(), 9, "Pending distribution amount should be 9");
    }

    function test_distributeRewards() public withRewardsDistributionWindow(1 days) {
        uint256 amount = 100 ether;

        uint256 totalAssetsBefore = pufferVault.totalAssets();

        vm.deal(address(revenueDepositor), amount);

        vm.startPrank(OPERATIONS_MULTISIG);
        revenueDepositor.depositRevenue();

        // 4 Wei precision loss
        // Right away, the pending distribution amount is the amount deposited to the Vault
        assertApproxEqAbs(
            revenueDepositor.getPendingDistributionAmount(),
            91 ether,
            4,
            "Pending distribution amount should be the amount deposited"
        );

        assertEq(pufferVault.totalAssets(), totalAssetsBefore, "PufferVault should have the same total assets");

        vm.warp(block.timestamp + 1 days);

        assertApproxEqAbs(
            pufferVault.totalAssets(), totalAssetsBefore + 91 ether, 4, "PufferVault should have +91 ether assets"
        );
        // After the distribution window, the pending distribution amount is 0
        assertApproxEqAbs(
            revenueDepositor.getPendingDistributionAmount(), 0, 4, "Pending distribution amount should be 0"
        );

        vm.warp(block.timestamp + 10 days);

        assertApproxEqAbs(
            pufferVault.totalAssets(), totalAssetsBefore + 91 ether, 4, "PufferVault should have +91 ether assets"
        );
        // After the distribution window, the pending distribution amount is 0
        assertApproxEqAbs(
            revenueDepositor.getPendingDistributionAmount(), 0, 4, "Pending distribution amount should be 0"
        );
    }

    function testRevert_nothingToDistribute() public {
        vm.startPrank(OPERATIONS_MULTISIG);
        vm.expectRevert(IPufferRevenueDepositor.NothingToDistribute.selector);
        revenueDepositor.depositRevenue();
    }

    function testRevert_vaultHasUndepositedRewards() public withRewardsDistributionWindow(1 days) {
        assertEq(block.timestamp, 1, "Timestamp should be 1");
        deal(address(revenueDepositor), 100 ether);

        vm.startPrank(OPERATIONS_MULTISIG);
        revenueDepositor.depositRevenue();

        deal(address(revenueDepositor), 100 ether);

        vm.expectRevert(IPufferRevenueDepositor.VaultHasUndepositedRewards.selector);
        revenueDepositor.depositRevenue();
    }

    function test_setRnoRewardsBps() public {
        uint256 oldFeeBps = revenueDepositor.getRnoRewardsBps();
        uint256 newFeeBps = 100;

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferRevenueDepositor.RnoRewardsBpsChanged(oldFeeBps, newFeeBps);
        revenueDepositor.setRnoRewardsBps(uint128(newFeeBps));
    }

    function test_setTreasuryRewardsBps() public {
        uint256 oldFeeBps = revenueDepositor.getTreasuryRewardsBps();
        uint256 newFeeBps = 100;

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferRevenueDepositor.TreasuryRewardsBpsChanged(oldFeeBps, newFeeBps);
        revenueDepositor.setTreasuryRewardsBps(uint128(newFeeBps));
    }

    function testRevert_setRnoRewardsBps_InvalidBps() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferRevenueDepositor.InvalidBps.selector);
        revenueDepositor.setRnoRewardsBps(uint128(1001));
    }

    function testRevert_setTreasuryRewardsBps_InvalidBps() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferRevenueDepositor.InvalidBps.selector);
        revenueDepositor.setTreasuryRewardsBps(uint128(2000));
    }

    function testRevert_removeRestakingOperator_NotOperator() public {
        vm.startPrank(OPERATIONS_MULTISIG);
        vm.expectRevert(IPufferRevenueDepositor.RestakingOperatorNotSet.selector);
        revenueDepositor.removeRestakingOperator(address(1));
    }

    function testRevert_addRestakingOperators_InvalidOperatorZeroAddress() public {
        vm.startPrank(OPERATIONS_MULTISIG);

        address[] memory operators = new address[](1);
        operators[0] = address(0);

        vm.expectRevert(InvalidAddress.selector);
        revenueDepositor.addRestakingOperators(operators);
    }

    function test_addAndRemoveRestakingOperator() public {
        vm.startPrank(OPERATIONS_MULTISIG);

        address newOperator = makeAddr("operator50");

        address[] memory operators = new address[](1);
        operators[0] = newOperator;

        vm.expectEmit(true, true, true, true);
        emit IPufferRevenueDepositor.RestakingOperatorAdded(operators[0]);
        revenueDepositor.addRestakingOperators(operators);

        vm.expectRevert(IPufferRevenueDepositor.RestakingOperatorAlreadySet.selector);
        revenueDepositor.addRestakingOperators(operators);

        vm.expectEmit(true, true, true, true);
        emit IPufferRevenueDepositor.RestakingOperatorRemoved(newOperator);
        revenueDepositor.removeRestakingOperator(newOperator);
    }

    function test_depositRestakingRewardsInstantly() public {
        // Deposit WETH 100 ETH to the Depositor contract
        vm.deal(address(this), 100 ether);
        weth.deposit{ value: 90 ether }();

        // Transfer 90 WETH and 10 ETH, the contract should wrap the 10 ETH
        weth.transfer(address(revenueDepositor), 90 ether);
        (bool success,) = address(revenueDepositor).call{ value: 10 ether }("");
        require(success, "Transfer failed");

        uint256 totalAssetsBefore = pufferVault.totalAssets();

        assertEq(totalAssetsBefore, 1000 ether, "Total assets should be 1000 ETH");

        vm.startPrank(OPERATIONS_MULTISIG);
        // Trigger deposit of restaking rewards
        revenueDepositor.depositRevenue();

        assertEq(
            revenueDepositor.getLastDepositTimestamp(), 1, "Last deposit timestamp should be the current timestamp 1"
        );

        // We have precision loss from the RNO rewards distribution, 4 wei is going to the Vault because of the rounding
        assertApproxEqAbs(
            pufferVault.totalAssets(), totalAssetsBefore + 91 ether, 4, "Total assets should be 91 ETH more"
        );

        assertEq(weth.balanceOf(address(revenueDepositor.TREASURY())), 5 ether, "Treasury should have 5 WETH");
        assertEq(weth.balanceOf(RNO1), 0.571428571428571428 ether, "RNO1 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO2), 0.571428571428571428 ether, "RNO1 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO3), 0.571428571428571428 ether, "RNO3 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO4), 0.571428571428571428 ether, "RNO4 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO5), 0.571428571428571428 ether, "RNO5 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO6), 0.571428571428571428 ether, "RNO6 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO7), 0.571428571428571428 ether, "RNO7 should have 0.571428571428571428 WETH");
    }
}
