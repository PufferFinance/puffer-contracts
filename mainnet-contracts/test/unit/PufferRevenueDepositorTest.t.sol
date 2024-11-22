// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IPufferRevenueDepositor } from "src/interface/IPufferRevenueDepositor.sol";
import { IWETH } from "src/interface/IWETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ROLE_ID_REVENUE_DEPOSITOR } from "../../script/Roles.sol";

struct AssetValue {
    IERC20 asset;
    uint256 value;
}

contract AeraVaultMock {
    IWETH public immutable WETH;
    uint256 public reservedFees;

    constructor(address weth) {
        WETH = IWETH(weth);
    }

    function setReservedFees(uint256 _reservedFees) external {
        reservedFees = _reservedFees;
    }

    function withdraw(AssetValue[] calldata amounts) external {
        // Get available balance after fees
        uint256 totalBalance = WETH.balanceOf(address(this));
        uint256 availableBalance = totalBalance > reservedFees ? totalBalance - reservedFees : 0;

        require(amounts[0].value <= availableBalance, "No WETH available to withdraw");

        WETH.transfer(msg.sender, amounts[0].value);
    }

    function holdings() external view returns (AssetValue[] memory) {
        AssetValue[] memory assetValues = new AssetValue[](1);
        uint256 totalBalance = WETH.balanceOf(address(this));
        uint256 availableBalance = totalBalance > reservedFees ? totalBalance - reservedFees : 0;
        assetValues[0] = AssetValue({ asset: IERC20(address(WETH)), value: availableBalance });
        return assetValues;
    }
}

/**
 * @title PufferRevenueDepositorTest
 * @dev Test contract for PufferRevenueDepositor
 *
 * @dev Run the following command to execute the tests:
 * forge test --mc PufferRevenueDepositorTest -vvvv
 */
contract PufferRevenueDepositorTest is UnitTestHelper {
    AeraVaultMock public aeraVault;

    function setUp() public override {
        super.setUp();

        // Get the expected AeraVault address from revenueDepositor
        address expectedVaultAddress = address(revenueDepositor.AERA_VAULT());

        // Deploy mock at the expected address
        vm.etch(expectedVaultAddress, address(new AeraVaultMock(address(weth))).code);
        aeraVault = AeraVaultMock(expectedVaultAddress);

        // Deposit 1000 WETH to the AeraVault
        deal(address(weth), address(aeraVault), 1000 ether);

        vm.prank(address(timelock));
        // Grant the revenue depositor role to the revenue depositor itself so that we can use callTargets to withdraw & deposit in 1 tx
        accessManager.grantRole(ROLE_ID_REVENUE_DEPOSITOR, address(revenueDepositor), 0);
    }

    function test_setup() public view {
        assertEq(address(aeraVault.WETH()), address(weth), "WETH should be the same");
        assertEq(weth.balanceOf(address(aeraVault)), 1000 ether, "AeraVault should have 1000 WETH");

        assertEq(address(revenueDepositor.AERA_VAULT()), address(aeraVault), "AeraVault should be the same");
    }

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

        revenueDepositor.depositRevenue();

        assertEq(revenueDepositor.getPendingDistributionAmount(), 1, "Pending distribution amount should be 1");

        // After half of the distribution window, the pending distribution amount is half of the total amount
        vm.warp(block.timestamp + 12 hours);

        assertEq(revenueDepositor.getPendingDistributionAmount(), 0, "Pending distribution amount should be 0");
    }

    function test_distributeRewards() public withRewardsDistributionWindow(1 days) {
        uint256 amount = 100 ether;

        uint256 totalAssetsBefore = pufferVault.totalAssets();

        vm.deal(address(revenueDepositor), amount);

        vm.startPrank(OPERATIONS_MULTISIG);
        revenueDepositor.depositRevenue();

        // 4 Wei precision loss
        // Right away, the pending distribution amount is the amount deposited to the Vault
        assertEq(
            revenueDepositor.getPendingDistributionAmount(), 100 ether, "Pending distribution amount should be 100 ETH"
        );

        assertEq(pufferVault.totalAssets(), totalAssetsBefore, "PufferVault should have the same total assets");

        vm.warp(block.timestamp + 1 days);

        assertEq(pufferVault.totalAssets(), totalAssetsBefore + 100 ether, "PufferVault should have +100 ether assets");
        // After the distribution window, the pending distribution amount is 0
        assertEq(revenueDepositor.getPendingDistributionAmount(), 0, "Pending distribution amount should be 0");

        vm.warp(block.timestamp + 10 days);

        assertEq(pufferVault.totalAssets(), totalAssetsBefore + 100 ether, "PufferVault should have +100 ether assets");
        // After the distribution window, the pending distribution amount is 0
        assertEq(revenueDepositor.getPendingDistributionAmount(), 0, "Pending distribution amount should be 0");
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

        assertEq(pufferVault.totalAssets(), totalAssetsBefore + 100 ether, "Total assets should be 100 ETH more");
    }

    // Withdraw 100 WETH from AeraVault and deposit it into PufferVault in 1 tx
    function test_callTargets() public {
        vm.startPrank(OPERATIONS_MULTISIG);

        address[] memory targets = new address[](2);
        targets[0] = address(aeraVault);
        targets[1] = address(revenueDepositor);

        bytes[] memory data = new bytes[](2);

        // Create withdrawal request with proper AssetValue array
        AssetValue[] memory withdrawalAssets = new AssetValue[](1);
        withdrawalAssets[0] = AssetValue({ asset: IERC20(address(weth)), value: 100 ether });

        data[0] = abi.encodeCall(aeraVault.withdraw, (withdrawalAssets));
        data[1] = abi.encodeCall(revenueDepositor.depositRevenue, ());

        vm.expectEmit(true, true, true, true);
        emit IPufferRevenueDepositor.RevenueDeposited(100 ether);
        revenueDepositor.callTargets(targets, data);
    }

    function test_withdrawAndDepositWithFees() public {
        uint256 initialAmount = 100 ether;
        deal(address(weth), address(aeraVault), initialAmount);

        // Set reserved fees in mock vault (20%)
        uint256 reservedFees = 20 ether;
        aeraVault.setReservedFees(reservedFees);

        uint256 pufferVaultBalanceBefore = weth.balanceOf(address(pufferVault));

        vm.prank(OPERATIONS_MULTISIG);
        revenueDepositor.withdrawAndDeposit();

        assertEq(
            weth.balanceOf(address(pufferVault)) - pufferVaultBalanceBefore,
            initialAmount - reservedFees,
            "Should deposit available amount minus fees"
        );
    }

    function testRevert_withdrawAndDepositAllReservedForFees() public {
        uint256 initialAmount = 100 ether;
        deal(address(weth), address(aeraVault), initialAmount);

        // Set reserved fees to total balance
        aeraVault.setReservedFees(initialAmount);

        vm.prank(OPERATIONS_MULTISIG);
        vm.expectRevert(IPufferRevenueDepositor.NothingToWithdraw.selector);
        revenueDepositor.withdrawAndDeposit();
    }
}
