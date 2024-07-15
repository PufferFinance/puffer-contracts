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
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IConnext } from "./interface/Connext/IConnext.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IXERC20Lockbox } from "./interface/IXERC20Lockbox.sol";

/**
 * @title PufferVaultV3
 * @dev Implementation of the PufferVault version 3 contract.
 * @notice This contract extends the functionality of PufferVaultV2 with additional features for reward minting and bridging.
 * @custom:security-contact security@puffer.fi
 */
contract PufferVaultV3 is PufferVaultV2, IPufferVaultV3 {
    // The Connext contract on the origin domain.
    IConnext public immutable _CONNEXT;
    // The token to be paid on this domain.
    IERC20 public immutable XTOKEN;
    // The lockbox contract for xToken.
    IXERC20Lockbox public immutable LOCKBOX;
    // The destination domain ID for bridging.
    uint32 public immutable _DESTINATION_DOMAIN;
    // The address of the L2 reward manager.
    address public immutable L2_REWARD_MANAGER;

    // Slippage constant used in bridging transactions.
    uint256 internal constant _SLIPPAGE = 0;

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
        _CONNEXT = IConnext(bridgingConstructorParams.connext);
        XTOKEN = IERC20(bridgingConstructorParams.xToken);
        _DESTINATION_DOMAIN = bridgingConstructorParams.destinationDomain;
        LOCKBOX = IXERC20Lockbox(bridgingConstructorParams.lockBox);
        L2_REWARD_MANAGER = bridgingConstructorParams.l2RewardManager;
        _disableInitializers();
    }

    /**
     * @notice Fallback function to receive ETH.
     */
    receive() external payable virtual override { }

    /**
     * @notice Returns the total assets held by the vault.
     * @dev See {IERC4626-totalAssets}. pufETH, the shares of the vault, will be backed primarily by the WETH asset.
     * However, at any point in time, the full backings may be a combination of stETH, WETH, Eigenpod ETH Rewards and ETH.
     * `totalAssets()` is calculated by summing the following:
     * - WETH held in the vault contract
     * - ETH held in the vault contract
     * - PUFFER_ORACLE.getLockedEthAmount(), which is the oracle-reported Puffer validator ETH locked in the Beacon chain
     * - stETH held in the vault contract, in EigenLayer's stETH strategy, and in Lido's withdrawal queue. (we assume stETH is always 1:1 with ETH since it's rebasing)
     * - ETH held in the eigenpods as a result of receiving rewards.
     * NOTE on the native ETH deposits:
     * When dealing with NATIVE ETH deposits, we need to deduct callvalue from the balance.
     * The contract calculates the amount of shares (pufETH) to mint based on the total assets.
     * When a user sends ETH, the msg.value is immediately added to address(this).balance.
     * Since address(this.balance)` is used in calculating `totalAssets()`, we must deduct the `callvalue()` from the balance to prevent the user from minting excess shares.
     * `msg.value` cannot be accessed from a view function, so we use assembly to get the callvalue.
     * @return The total assets held by the vault.
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 callValue;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            callValue := callvalue()
        }
        return _ST_ETH.balanceOf(address(this)) + getPendingLidoETHAmount() + getELBackingEthAmount()
            + _WETH.balanceOf(address(this)) + (address(this).balance - callValue) + PUFFER_ORACLE.getLockedEthAmount()
            + getTotalRewardMintAmount();
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
    function mintAndBridgeRewards(BridgingParams calldata params) external payable restricted {
        VaultStorage storage $ = _getPufferVaultStorage();

        if (params.rewardsAmount > $.allowedRewardMintAmount) {
            revert InvalidMintAmount();
        }

        if (($.lastRewardMintTimestamp + $.allowedRewardMintFrequency) > block.timestamp) {
            revert NotAllowedMintFrequency();
        }

        $.lastRewardMintTimestamp = uint40(block.timestamp);
        $.totalRewardMintAmount += uint104(params.rewardsAmount);

        _mint(address(this), params.rewardsAmount);
        _approve(address(this), address(LOCKBOX), params.rewardsAmount);
        LOCKBOX.deposit(params.rewardsAmount);

        // This contract approves transfer to Connext
        XTOKEN.approve(address(_CONNEXT), params.rewardsAmount);

        // Encode calldata for the target contract call
        bytes memory callData = abi.encode(params);

        _CONNEXT.xcall{ value: msg.value }(
            _DESTINATION_DOMAIN, // _destination: Domain ID of the destination chain
            L2_REWARD_MANAGER, // _to: address of the target contract
            address(XTOKEN), // _asset: address of the token contract
            msg.sender, // _delegate: address that can revert or forceLocal on destination
            params.rewardsAmount, // _amount: amount of tokens to transfer
            _SLIPPAGE, // _slippage: max slippage the user will accept in BPS (e.g. 300 = 3%)
            callData // _callData: the encoded calldata to send
        );

        emit MintedAndBridgedRewards(
            params.rewardsAmount, params.startEpoch, params.endEpoch, params.rewardsRoot, params.rewardsURI
        );
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
     * @notice Authorizes the upgrade to a new implementation.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
