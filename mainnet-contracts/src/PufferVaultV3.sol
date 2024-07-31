// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV2 } from "./PufferVaultV2.sol";
import { IStETH } from "./interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "./interface/Lido/ILidoWithdrawalQueue.sol";
import { IEigenLayer } from "./interface/EigenLayer/IEigenLayer.sol";
import { IStrategy } from "./interface/EigenLayer/IStrategy.sol";
import { IDelegationManager } from "./interface/EigenLayer/IDelegationManager.sol";
import { IWETH } from "./interface/Other/IWETH.sol";
import { IPufferVaultV3 } from "./interface/IPufferVaultV3.sol";
import { IPufferOracle } from "./interface/IPufferOracle.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBridgeInterface } from "./interface/Connext/IBridgeInterface.sol";
import { IXERC20Lockbox } from "./interface/IXERC20Lockbox.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title PufferVaultV3
 * @dev Implementation of the PufferVault version 3 contract.
 * @notice This contract extends the functionality of PufferVaultV2 with additional features for reward minting and bridging.
 * @custom:security-contact security@puffer.fi
 */
contract PufferVaultV3 is PufferVaultV2, IPufferVaultV3 {
    using Math for uint256;

    // The token to be paid on this domain.
    IERC20 public immutable XPUFETH;
    // The lockbox contract for xToken.
    IXERC20Lockbox public immutable LOCKBOX;
    // The address of the L2 reward manager.
    address public immutable L2_REWARD_MANAGER;

    /**
     * @notice Initializes the PufferVaultV3 contract.
     * @param stETH Address of the stETH token contract.
     * @param weth Address of the WETH token contract.
     * @param lidoWithdrawalQueue Address of the Lido withdrawal queue contract.
     * @param stETHStrategy Address of the stETH strategy contract.
     * @param eigenStrategyManager Address of the EigenLayer strategy manager contract.
     * @param oracle Address of the PufferOracle contract.
     * @param delegationManager Address of the delegation manager contract.
     * @param bridgingConstructorParams Constructor parameters for bridging.
     */
    constructor(
        IStETH stETH,
        IWETH weth,
        ILidoWithdrawalQueue lidoWithdrawalQueue,
        IStrategy stETHStrategy,
        IEigenLayer eigenStrategyManager,
        IPufferOracle oracle,
        IDelegationManager delegationManager,
        BridgingConstructorParams memory bridgingConstructorParams
    ) PufferVaultV2(stETH, weth, lidoWithdrawalQueue, stETHStrategy, eigenStrategyManager, oracle, delegationManager) {
        XPUFETH = IERC20(bridgingConstructorParams.xToken);
        LOCKBOX = IXERC20Lockbox(bridgingConstructorParams.lockBox);
        L2_REWARD_MANAGER = bridgingConstructorParams.l2RewardManager;
        _disableInitializers();
    }

    /**
     * @notice Returns the total assets held by the vault.
     * @dev Returns the total assets held by the vault, including ETH held in the eigenpods as a result of receiving rewards.
     * @return The total assets held by the vault.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return (super.totalAssets() + getTotalRewardMintAmount());
    }

    /**
     * @notice Returns the total reward mint amount.
     * @return The total reward mint amount.
     */
    function getTotalRewardMintAmount() internal view returns (uint256) {
        VaultStorage storage $ = _getPufferVaultStorage();
        return $.totalRewardMintAmount;
    }

    /**
     * @notice Mints and bridges rewards according to the provided parameters.
     * @param params The parameters for bridging rewards.
     */
    function mintAndBridgeRewards(MintAndBridgeParams calldata params) external restricted {
        VaultStorage storage $ = _getPufferVaultStorage();

        if (params.rewardsAmount > $.allowedRewardMintAmount) {
            revert InvalidMintAmount();
        }

        if (($.lastRewardMintTimestamp + $.allowedRewardMintFrequency) > block.timestamp) {
            revert NotAllowedMintFrequency();
        }

        BridgeData memory bridgeData = $.bridges[params.bridge];

        if (bridgeData.destinationDomainId == 0) {
            revert BridgeNotAllowlisted();
        }

        uint256 ethToPufETHRate = convertToShares(1 ether);
        // calculate the shares using this formula since calling convertToShares again is costly
        uint256 shares = ethToPufETHRate.mulDiv(params.rewardsAmount, 1 ether, Math.Rounding.Floor);

        $.lastRewardMintTimestamp = uint40(block.timestamp);
        $.totalRewardMintAmount += uint104(params.rewardsAmount);

        _mint(address(this), shares);
        _approve(address(this), address(LOCKBOX), shares);
        LOCKBOX.deposit(shares);

        // This contract approves transfer to the bridge
        XPUFETH.approve(address(params.bridge), shares);

        MintAndBridgeData memory bridgingCalldata = MintAndBridgeData({
            rewardsAmount: params.rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: params.startEpoch,
            endEpoch: params.endEpoch,
            rewardsRoot: params.rewardsRoot,
            rewardsURI: params.rewardsURI
        });

        BridgingParams memory bridgingParams =
            BridgingParams({ bridgingType: BridgingType.MintAndBridge, data: abi.encode(bridgingCalldata) });

        // Encode data for the target contract call
        bytes memory encodedData = abi.encode(bridgingParams);

        IBridgeInterface(params.bridge).xcall({
            destination: bridgeData.destinationDomainId, // Domain ID of the destination chain
            to: L2_REWARD_MANAGER, // Address of the target contract
            asset: address(XPUFETH), // Address of the token contract
            delegate: msg.sender, // Address that can revert or forceLocal on destination
            amount: shares, // Amount of tokens to transfer
            slippage: 0, // Max slippage the user will accept in BPS (e.g. 300 = 3%)
            callData: encodedData // Encoded data to send
         });

        emit MintedAndBridgedRewards({
            rewardsAmount: params.rewardsAmount,
            startEpoch: params.startEpoch,
            endEpoch: params.endEpoch,
            rewardsRoot: params.rewardsRoot,
            ethToPufETHRate: ethToPufETHRate,
            rewardsURI: params.rewardsURI
        });
    }

    /**
     * @notice Sets the L2 reward claimer.
     * @param bridge The address of the bridge.
     * @param claimer The address of the new claimer.
     * @dev Restricted in this context is like the `whenNotPaused` modifier from Pausable.sol
     */
    function setL2RewardClaimer(address bridge, address claimer) external restricted {
        VaultStorage storage $ = _getPufferVaultStorage();
        BridgeData memory bridgeData = $.bridges[bridge];

        if (bridgeData.destinationDomainId == 0) {
            revert BridgeNotAllowlisted();
        }

        SetClaimerParams memory params = SetClaimerParams({ account: msg.sender, claimer: claimer });

        BridgingParams memory bridgingParams =
            BridgingParams({ bridgingType: BridgingType.SetClaimer, data: abi.encode(params) });

        // Encode data for the target contract call
        bytes memory encodedData = abi.encode(bridgingParams);

        IBridgeInterface(bridge).xcall({
            destination: bridgeData.destinationDomainId, // Domain ID of the destination chain
            to: L2_REWARD_MANAGER, // Address of the target contract
            asset: address(0), // Address of the token contract
            delegate: msg.sender, // Address that can revert or forceLocal on destination
            amount: 0, // Amount of tokens to transfer
            slippage: 0, // Max slippage the user will accept in BPS (e.g. 300 = 3%)
            callData: encodedData // Encoded data to send
         });

        emit L2RewardClaimerUpdated(msg.sender, claimer);
    }

    /**
     * @notice Sets the allowed reward mint amount.
     * @param newAmount The new allowed reward mint amount.
     */
    function setAllowedRewardMintAmount(uint88 newAmount) external restricted {
        VaultStorage storage $ = _getPufferVaultStorage();

        emit AllowedRewardMintAmountUpdated($.allowedRewardMintAmount, newAmount);

        $.allowedRewardMintAmount = newAmount;
    }

    /**
     * @notice Sets the allowed reward mint frequency.
     * @param newFrequency The new allowed reward mint frequency.
     */
    function setAllowedRewardMintFrequency(uint24 newFrequency) external restricted {
        VaultStorage storage $ = _getPufferVaultStorage();

        emit AllowedRewardMintFrequencyUpdated($.allowedRewardMintFrequency, newFrequency);

        $.allowedRewardMintFrequency = newFrequency;
    }

    /**
     * @notice Updates the bridge data.
     * @param bridge The address of the bridge.
     * @param bridgeData The updated bridge data.
     */
    function updateBridgeData(address bridge, BridgeData memory bridgeData) external restricted {
        VaultStorage storage $ = _getPufferVaultStorage();
        if (bridge == address(0)) {
            revert InvalidAddress();
        }

        $.bridges[bridge].destinationDomainId = bridgeData.destinationDomainId;
        emit BridgeDataUpdated(bridge, bridgeData);
    }

    /**
     * @notice Returns the bridge data for a given bridge.
     * @param bridge The address of the bridge.
     * @return The bridge data.
     */
    function getBridge(address bridge) external view returns (BridgeData memory) {
        VaultStorage storage $ = _getPufferVaultStorage();

        return $.bridges[bridge];
    }
}
