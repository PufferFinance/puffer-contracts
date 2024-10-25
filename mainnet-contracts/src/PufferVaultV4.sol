// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IStETH } from "./interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "./interface/Lido/ILidoWithdrawalQueue.sol";
import { IEigenLayer } from "./interface/EigenLayer/IEigenLayer.sol";
import { IStrategy } from "./interface/EigenLayer/IStrategy.sol";
import { IDelegationManager } from "./interface/EigenLayer/IDelegationManager.sol";
import { IWETH } from "./interface/Other/IWETH.sol";
import { IPufferOracle } from "./interface/IPufferOracle.sol";
import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IPufferRevenueDepositor } from "./interface/IPufferRevenueDepositor.sol";

/**
 * @title PufferVaultV4
 * @dev Implementation of the PufferVault version 4 contract.
 * @notice This contract extends the functionality of PufferVaultV3 with additional features for restaking rewards.
 * @custom:security-contact security@puffer.fi
 * @custom:oz-upgrades-from src/PufferVaultV3.sol:PufferVaultV3
 */
contract PufferVaultV4 is PufferVaultV3 {
    using SafeCast for uint256;

    /**
     * @notice The restaking rewards depositor contract.
     */
    IPufferRevenueDepositor public immutable RESTAKING_REWARDS_DEPOSITOR;

    /**
     * @notice Initializes the PufferVaultV3 contract.
     * @param stETH Address of the stETH token contract.
     * @param weth Address of the WETH token contract.
     * @param lidoWithdrawalQueue Address of the Lido withdrawal queue contract.
     * @param stETHStrategy Address of the stETH strategy contract.
     * @param eigenStrategyManager Address of the EigenLayer strategy manager contract.
     * @param oracle Address of the PufferOracle contract.
     * @param delegationManager Address of the delegation manager contract.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(
        IStETH stETH,
        IWETH weth,
        ILidoWithdrawalQueue lidoWithdrawalQueue,
        IStrategy stETHStrategy,
        IEigenLayer eigenStrategyManager,
        IPufferOracle oracle,
        IDelegationManager delegationManager,
        IPufferRevenueDepositor revenueDepositor
    ) PufferVaultV3(stETH, weth, lidoWithdrawalQueue, stETHStrategy, eigenStrategyManager, oracle, delegationManager) {
        RESTAKING_REWARDS_DEPOSITOR = revenueDepositor;
        _disableInitializers();
    }

    /**
     * @notice Returns the total assets of the vault.
     * @dev This is the total assets of the vault minus the pending distribution amount.
     * @return The total assets of the vault.
     */
    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() - RESTAKING_REWARDS_DEPOSITOR.getPendingDistributionAmount();
    }
}
