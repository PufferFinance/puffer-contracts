// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { DeployRevenueDepositor } from "../../script/DeployRevenueDepositor.s.sol";
import { PufferRevenueDepositor } from "../../src/PufferRevenueDepositor.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ROLE_ID_REVENUE_DEPOSITOR } from "../../script/Roles.sol";
import { IPufferRevenueDepositor } from "../../src/interface/IPufferRevenueDepositor.sol";
import { PufferVaultV4 } from "../../src/PufferVaultV4.sol";
import { IStETH } from "../../src/interface/Lido/IStETH.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";
import { ILidoWithdrawalQueue } from "../../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IStrategy } from "../../src/interface/EigenLayer/IStrategy.sol";
import { IEigenLayer } from "../../src/interface/EigenLayer/IEigenLayer.sol";
import { IPufferOracle } from "../../src/interface/IPufferOracle.sol";
import { IDelegationManager } from "../../src/interface/EigenLayer/IDelegationManager.sol";

struct AssetValue {
    IERC20 asset;
    uint256 value;
}

interface IAeraVault {
    function withdraw(AssetValue[] calldata amounts) external;
}

contract PufferRevenueDepositorForkTest is MainnetForkTestHelper {
    PufferRevenueDepositor public revenueDepositor;

    uint24 public constant REWARDS_DISTRIBUTION_WINDOW = 1 days;

    function setUp() public virtual override {
        // Cancun upgrade
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21112808); // (Nov-04-2024 07:31:35 AM +UTC)

        // Setup contracts that are deployed to mainnet
        _setupLiveContracts();

        // Deploy revenue depositor
        DeployRevenueDepositor depositorDeployer = new DeployRevenueDepositor();
        depositorDeployer.run();
        revenueDepositor = depositorDeployer.revenueDepositor();

        // Upgrade PufferVault to V4
        address newVault = address(
            new PufferVaultV4(
                IStETH(_getStETH()),
                IWETH(_getWETH()),
                ILidoWithdrawalQueue(_getLidoWithdrawalQueue()),
                IStrategy(_getStETHStrategy()),
                IEigenLayer(_getEigenLayerStrategyManager()),
                IPufferOracle(_getPufferOracle()),
                IDelegationManager(_getDelegationManager()),
                revenueDepositor
            )
        );

        // Setup AccessManager
        vm.startPrank(_getTimelock());

        // Upgrade PufferVault to V4
        pufferVault.upgradeToAndCall(newVault, "");

        (bool success,) = address(accessManager).call(depositorDeployer.encodedCalldata());
        assertTrue(success, "Failed to deploy revenue depositor");

        // Transfer ownership of Aera vault to revenue depositor
        vm.startPrank(_getOPSMultisig());
        Ownable2Step(_getAeraVault()).transferOwnership(address(revenueDepositor));

        // Accept ownership of Aera vault
        address[] memory targets = new address[](1);
        targets[0] = address(_getAeraVault());
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(Ownable2Step.acceptOwnership, ());

        revenueDepositor.callTargets(targets, data);

        // Grant the revenue depositor role to the revenue depositor itesels so that we can use callTargets to withdraw & deposit in 1 tx
        vm.startPrank(_getTimelock());
        accessManager.grantRole(ROLE_ID_REVENUE_DEPOSITOR, address(revenueDepositor), 0);

        // Set rewards distribution window to 1 day
        vm.startPrank(_getDAO());
        revenueDepositor.setRewardsDistributionWindow(REWARDS_DISTRIBUTION_WINDOW);

        vm.stopPrank();
    }

    function test_sanity() public view {
        assertTrue(address(revenueDepositor) != address(0), "Revenue depositor not deployed");
        assertEq(
            pufferVault.convertToAssets(1 ether),
            1.026019081620562074 ether,
            "1 pufETH should be 1.026019081620562074 WETH"
        );
    }

    function test_deposit_revenue() public {
        vm.startPrank(_getOPSMultisig());

        uint256 wethBalance = IERC20(_getWETH()).balanceOf(_getAeraVault());

        AssetValue[] memory assets = new AssetValue[](1);
        assets[0] = AssetValue({ asset: IERC20(_getWETH()), value: wethBalance });

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IAeraVault(_getAeraVault()).withdraw, (assets));

        address[] memory targets = new address[](1);
        targets[0] = address(_getAeraVault());

        revenueDepositor.callTargets(targets, data);

        vm.expectEmit(true, true, true, true);
        emit IPufferRevenueDepositor.RevenueDeposited(wethBalance);
        revenueDepositor.depositRevenue();
    }

    function test_withdrawAndDeposit() public {
        vm.startPrank(_getOPSMultisig());

        uint256 wethBalance = IERC20(_getWETH()).balanceOf(_getAeraVault());

        vm.expectEmit(true, true, true, true);
        emit IPufferRevenueDepositor.RevenueDeposited(wethBalance);
        revenueDepositor.withdrawAndDeposit();
    }

    // Deposit revenue from Aera Vault to Puffer Vault
    function test_deposit_weth_to_puffer_vault() public {
        vm.startPrank(_getOPSMultisig());

        address[] memory targets = new address[](2);
        targets[0] = address(_getAeraVault());
        targets[1] = address(revenueDepositor);

        uint256 wethBalance = IERC20(_getWETH()).balanceOf(_getAeraVault());

        uint256 vaultWethBalance = IERC20(_getWETH()).balanceOf(address(pufferVault));
        uint256 pufferVaultAssetsBefore = pufferVault.totalAssets();

        assertEq(pufferVaultAssetsBefore, 317212543571614106164392, "Puffer Vault Assets before");
        assertEq(vaultWethBalance, 0, "Puffer Vault should have 0 WETH before deposit");
        assertEq(wethBalance, 67.612355147076514123 ether, "Aera Vault should have 67.612355147076514123 WETH");

        AssetValue[] memory assets = new AssetValue[](1);
        assets[0] = AssetValue({ asset: IERC20(_getWETH()), value: wethBalance });

        // 1. Withdraw WETH from Aera Vault -> Owner (Revenue Depositor)
        // 2. Deposit WETH into Puffer Vault -> Revenue Depositor
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IAeraVault(_getAeraVault()).withdraw, (assets));
        data[1] = abi.encodeCall(revenueDepositor.depositRevenue, ());

        vm.expectEmit(true, true, true, true);
        emit IPufferRevenueDepositor.RevenueDeposited(wethBalance);
        revenueDepositor.callTargets(targets, data);

        uint256 wethBalanceAfter = IERC20(_getWETH()).balanceOf(_getAeraVault());
        assertEq(wethBalanceAfter, 0, "Aera Vault should have 0 WETH after deposit");

        assertEq(
            IERC20(_getWETH()).balanceOf(address(pufferVault)),
            vaultWethBalance + wethBalance,
            "Puffer Vault received WETH"
        );

        // Assets after in the same block are the same
        assertEq(pufferVault.totalAssets(), pufferVaultAssetsBefore, "Puffer Vault total assets after");

        vm.warp(block.timestamp + REWARDS_DISTRIBUTION_WINDOW);

        // Everything is deposited
        assertEq(
            pufferVault.totalAssets(),
            pufferVaultAssetsBefore + wethBalance,
            "Puffer Vault total assets after everything is deposited"
        );
    }
}
