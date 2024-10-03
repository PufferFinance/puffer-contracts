// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PufferVaultV3 } from "../../src/PufferVaultV3.sol";
import { IStETH } from "../../src/interface/Lido/IStETH.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";
import { ILidoWithdrawalQueue } from "../../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IStrategy } from "../../src/interface/EigenLayer/IStrategy.sol";
import { IEigenLayer } from "../../src/interface/EigenLayer/IEigenLayer.sol";
import { IPufferOracle } from "../../src/interface/IPufferOracle.sol";
import { IDelegationManager } from "../../src/interface/EigenLayer/IDelegationManager.sol";
import "forge-std/console.sol";

contract V4Vault is PufferVaultV3 {
    uint256 depositRate;
    uint256 lastDepositTimestamp;
    uint256 lastDepositAmount;

    constructor(
        IStETH stETH,
        IWETH weth,
        ILidoWithdrawalQueue lidoWithdrawalQueue,
        IStrategy stETHStrategy,
        IEigenLayer eigenStrategyManager,
        IPufferOracle oracle,
        IDelegationManager delegationManager
    ) PufferVaultV3(stETH, weth, lidoWithdrawalQueue, stETHStrategy, eigenStrategyManager, oracle, delegationManager) { }

    function depositRestakingRewards() public payable {
        //@todo should be restricted to depositor contract
        lastDepositTimestamp = block.timestamp;
        lastDepositAmount = msg.value;
        depositRate = msg.value / 6 hours;
    }

    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() - getUndepositedAmount();
    }

    /**
     * @dev We deposit the ETH to the vault, but we don't account for it immediately.
     */
    function getUndepositedAmount() public view returns (uint256) {
        uint256 timePassed = block.timestamp - lastDepositTimestamp;
        uint256 totalDecayTime = 6 hours; // Fixed decay time of 6 hours

        if (timePassed >= totalDecayTime) {
            return 0;
        }

        uint256 remainingAmount = lastDepositAmount * (totalDecayTime - timePassed) / totalDecayTime;

        console.log("remainingAmount", remainingAmount);

        return remainingAmount;
    }
}

contract PufferVaultV3ForkTest is MainnetForkTestHelper {
    V4Vault v4Vault;

    function setUp() public virtual override {
        // Cancun upgrade
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20883447);

        // Setup contracts that are deployed to mainnet
        _setupLiveContracts();

        // Upgrade to latest version
        v4Vault = new V4Vault(
            _ST_ETH,
            _WETH,
            _LIDO_WITHDRAWAL_QUEUE,
            _EIGEN_STETH_STRATEGY,
            _EIGEN_STRATEGY_MANAGER,
            IPufferOracle(_getPufferOracle()),
            _EIGEN_DELEGATION_MANGER
        );

        vm.startPrank(_getTimelock());
        UUPSUpgradeable(pufferVault).upgradeToAndCall(address(v4Vault), "");
        vm.stopPrank();

        v4Vault = V4Vault(payable(address(pufferVault)));
    }

    // Sanity check
    function test_sanity() public view {
        assertEq(pufferVault.name(), "pufETH", "name");
        assertEq(pufferVault.symbol(), "pufETH", "symbol");
        assertEq(pufferVault.decimals(), 18, "decimals");
        assertEq(pufferVault.asset(), address(_WETH), "asset");
        assertEq(pufferVault.getTotalRewardMintAmount(), 0, "0 rewards");
    }

    function test_slow_release_of_the_rewards_from_l2() public {
        uint256 amount = 10000 ether;
        deal(address(this), amount);

        uint256 startAmount = 533405.879191302739097253 ether;

        vm.warp(1);
        assertEq(v4Vault.totalAssets(), startAmount, "assets before deposit");

        // We deposit 10k ETH to the vault
        v4Vault.depositRestakingRewards{ value: amount }();

        // In the same block, we don't account for it immediately
        assertEq(v4Vault.totalAssets(), startAmount, "assets after deposit in the same block");

        vm.warp(1 + 12 seconds);
        assertEq(
            v4Vault.totalAssets(), startAmount + 5.555555555555555556 ether, "assets after 12 increased by ~ 5.5 ether"
        );

        vm.warp(1 + 6 hours);
        assertEq(v4Vault.totalAssets(), 533405.879191302739097253 ether + amount, "Amount is deposited after 6 hours");
    }
}
