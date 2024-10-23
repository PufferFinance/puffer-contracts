// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IPufferRestakingRewardsDepositor } from "src/interface/IPufferRestakingRewardsDepositor.sol";
import { InvalidAddress } from "src/Errors.sol";

/**
 * @title PufferRestakingRewardsDepositorTest
 * @dev Test contract for PufferRestakingRewardsDepositor
 *
 * @dev Run the following command to execute the tests:
 * forge test --mc PufferRestakingRewardsDepositorTest -vvvv
 */
contract PufferRestakingRewardsDepositorTest is UnitTestHelper {
    /**
     * @dev Modifier to set the rewards distribution window for the test
     */
    modifier withRewardsDistributionWindow(uint24 newRewardsDistributionWindow) {
        vm.startPrank(DAO);
        restakingRewardsDepositor.setRewardsDistributionWindow(newRewardsDistributionWindow);
        _;
        vm.stopPrank();
    }

    function test_sanity() public view {
        assertEq(restakingRewardsDepositor.getRnoRewardsBps(), 400, "RNO rewards bps should be 400");
        assertEq(restakingRewardsDepositor.getTreasuryRewardsBps(), 500, "Treasury rewards bps should be 500");
        assertEq(restakingRewardsDepositor.getRestakingOperators().length, 7, "Should have 7 restaking operators");
        assertTrue(restakingRewardsDepositor.TREASURY() != address(0), "Treasury should not be 0");
        assertTrue(address(restakingRewardsDepositor.WETH()) != address(0), "WETH should not be 0");
        assertTrue(address(restakingRewardsDepositor.PUFFER_VAULT()) != address(0), "PufferVault should not be 0");
    }

    function test_setRewardsDistributionWindow() public {
        assertEq(restakingRewardsDepositor.getRewardsDistributionWindow(), 0, "Rewards distribution window should be 0");

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferRestakingRewardsDepositor.RewardsDistributionWindowChanged(0, 1 days);
        restakingRewardsDepositor.setRewardsDistributionWindow(1 days);

        assertEq(
            restakingRewardsDepositor.getRewardsDistributionWindow(),
            1 days,
            "Rewards distribution window should be 1 days"
        );
    }

    function test_distributeRewards() public withRewardsDistributionWindow(1 days) {
        uint256 amount = 100 ether;

        uint256 totalAssetsBefore = pufferVault.totalAssets();

        vm.warp(1);

        vm.deal(address(restakingRewardsDepositor), amount);

        vm.startPrank(OPERATIONS_MULTISIG);
        restakingRewardsDepositor.depositRestakingRewards();

        // 4 Wei precision loss
        // Right away, the pending distribution amount is the amount deposited to the Vault
        assertApproxEqAbs(
            restakingRewardsDepositor.getPendingDistributionAmount(),
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
            restakingRewardsDepositor.getPendingDistributionAmount(), 0, 4, "Pending distribution amount should be 0"
        );

        vm.warp(block.timestamp + 10 days);

        assertApproxEqAbs(
            pufferVault.totalAssets(), totalAssetsBefore + 91 ether, 4, "PufferVault should have +91 ether assets"
        );
        // After the distribution window, the pending distribution amount is 0
        assertApproxEqAbs(
            restakingRewardsDepositor.getPendingDistributionAmount(), 0, 4, "Pending distribution amount should be 0"
        );
    }

    function testRevert_nothingToDistribute() public {
        vm.startPrank(OPERATIONS_MULTISIG);
        vm.expectRevert(IPufferRestakingRewardsDepositor.NothingToDistribute.selector);
        restakingRewardsDepositor.depositRestakingRewards();
    }

    function testRevert_vaultHasUndepositedRewards() public withRewardsDistributionWindow(1 days) {
        assertEq(block.timestamp, 1, "Timestamp should be 1");
        deal(address(restakingRewardsDepositor), 100 ether);

        vm.startPrank(OPERATIONS_MULTISIG);
        restakingRewardsDepositor.depositRestakingRewards();

        deal(address(restakingRewardsDepositor), 100 ether);

        vm.expectRevert(IPufferRestakingRewardsDepositor.VaultHasUndepositedRewards.selector);
        restakingRewardsDepositor.depositRestakingRewards();
    }

    function test_setRnoRewardsBps() public {
        uint256 oldFeeBps = restakingRewardsDepositor.getRnoRewardsBps();
        uint256 newFeeBps = 100;

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferRestakingRewardsDepositor.RnoRewardsBpsChanged(oldFeeBps, newFeeBps);
        restakingRewardsDepositor.setRnoRewardsBps(uint128(newFeeBps));
    }

    function test_setTreasuryRewardsBps() public {
        uint256 oldFeeBps = restakingRewardsDepositor.getTreasuryRewardsBps();
        uint256 newFeeBps = 100;

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IPufferRestakingRewardsDepositor.TreasuryRewardsBpsChanged(oldFeeBps, newFeeBps);
        restakingRewardsDepositor.setTreasuryRewardsBps(uint128(newFeeBps));
    }

    function testRevert_setRnoRewardsBps_InvalidBps() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferRestakingRewardsDepositor.InvalidBps.selector);
        restakingRewardsDepositor.setRnoRewardsBps(uint128(1001));
    }

    function testRevert_setTreasuryRewardsBps_InvalidBps() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferRestakingRewardsDepositor.InvalidBps.selector);
        restakingRewardsDepositor.setTreasuryRewardsBps(uint128(2000));
    }

    function testRevert_removeRestakingOperator_NotOperator() public {
        vm.startPrank(OPERATIONS_MULTISIG);
        vm.expectRevert(IPufferRestakingRewardsDepositor.RestakingOperatorNotSet.selector);
        restakingRewardsDepositor.removeRestakingOperator(address(1));
    }

    function testRevert_addRestakingOperators_InvalidOperatorZeroAddress() public {
        vm.startPrank(OPERATIONS_MULTISIG);

        address[] memory operators = new address[](1);
        operators[0] = address(0);

        vm.expectRevert(InvalidAddress.selector);
        restakingRewardsDepositor.addRestakingOperators(operators);
    }

    function test_addAndRemoveRestakingOperator() public {
        vm.startPrank(OPERATIONS_MULTISIG);

        address newOperator = makeAddr("operator50");

        address[] memory operators = new address[](1);
        operators[0] = newOperator;

        vm.expectEmit(true, true, true, true);
        emit IPufferRestakingRewardsDepositor.RestakingOperatorAdded(operators[0]);
        restakingRewardsDepositor.addRestakingOperators(operators);

        vm.expectEmit(true, true, true, true);
        emit IPufferRestakingRewardsDepositor.RestakingOperatorRemoved(newOperator);
        restakingRewardsDepositor.removeRestakingOperator(newOperator);
    }

    function test_depositRestakingRewardsInstantly() public {
        vm.warp(1);
        // Deposit WETH 100 ETH to the Depositor contract
        vm.deal(address(this), 100 ether);
        weth.deposit{ value: 90 ether }();

        // Transfer 90 WETH and 10 ETH, the contract should wrap the 10 ETH
        weth.transfer(address(restakingRewardsDepositor), 90 ether);
        (bool success,) = address(restakingRewardsDepositor).call{ value: 10 ether }("");
        require(success, "Transfer failed");

        uint256 totalAssetsBefore = pufferVault.totalAssets();

        assertEq(totalAssetsBefore, 1000 ether, "Total assets should be 1000 ETH");

        vm.startPrank(OPERATIONS_MULTISIG);
        // Trigger deposit of restaking rewards
        restakingRewardsDepositor.depositRestakingRewards();

        assertEq(
            restakingRewardsDepositor.getLastDepositTimestamp(),
            1,
            "Last deposit timestamp should be the current timestamp 1"
        );

        // We have precision loss from the RNO rewards distribution, 4 wei is going to the Vault because of the rounding
        assertApproxEqAbs(
            pufferVault.totalAssets(), totalAssetsBefore + 91 ether, 4, "Total assets should be 91 ETH more"
        );

        assertEq(weth.balanceOf(address(restakingRewardsDepositor.TREASURY())), 5 ether, "Treasury should have 5 WETH");
        assertEq(weth.balanceOf(RNO1), 0.571428571428571428 ether, "RNO1 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO2), 0.571428571428571428 ether, "RNO1 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO3), 0.571428571428571428 ether, "RNO3 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO4), 0.571428571428571428 ether, "RNO4 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO5), 0.571428571428571428 ether, "RNO5 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO6), 0.571428571428571428 ether, "RNO6 should have 0.571428571428571428 WETH");
        assertEq(weth.balanceOf(RNO7), 0.571428571428571428 ether, "RNO7 should have 0.571428571428571428 WETH");
    }
}
