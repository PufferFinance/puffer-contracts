// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IXReceiver } from "@connext/interfaces/core/IXReceiver.sol";
import { IXERC20Lockbox } from "./interface/IXERC20Lockbox.sol";
import { IL1RewardManager } from "./interface/IL1RewardManager.sol";
import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { L1RewardManagerStorage } from "./L1RewardManagerStorage.sol";
import { IBridgeInterface } from "./interface/Connext/IBridgeInterface.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";

/**
 * @title L1RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract L1RewardManager is
    IXReceiver,
    IL1RewardManager,
    L1RewardManagerStorage,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    using Math for uint256;

    /**
     * @notice The XPUFETH token contract on Ethereum Mainnet
     */
    IERC20 public immutable XPUFETH;
    /**
     * @notice The PufferVault contract on Ethereum Mainnet
     */
    PufferVaultV3 public immutable PUFFER_VAULT;
    /**
     * @notice The XERC20Lockbox contract on Ethereum Mainnet
     */
    IXERC20Lockbox public immutable LOCKBOX;
    /**
     * @notice The Rewards Manager contract on L2
     */
    address public immutable L2_REWARDS_MANAGER;

    constructor(address XpufETH, address lockbox, address pufETH, address l2RewardsManager) {
        XPUFETH = IERC20(XpufETH);
        LOCKBOX = IXERC20Lockbox(lockbox);
        PUFFER_VAULT = PufferVaultV3(payable(pufETH));
        L2_REWARDS_MANAGER = l2RewardsManager;
        _disableInitializers();
    }

    modifier onlyRewardsManager(address originSender) {
        if (originSender != address(L2_REWARDS_MANAGER)) {
            revert Unauthorized();
        }
        _;
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function setL2RewardClaimer(address bridge, address claimer) external payable {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        BridgeData memory bridgeData = $.bridges[bridge];

        if (bridgeData.destinationDomainId == 0) {
            revert BridgeNotAllowlisted();
        }

        SetClaimerParams memory params = SetClaimerParams({ account: msg.sender, claimer: claimer });

        BridgingParams memory bridgingParams =
            BridgingParams({ bridgingType: BridgingType.SetClaimer, data: abi.encode(params) });

        // Encode data for the target contract call
        bytes memory encodedData = abi.encode(bridgingParams);

        // we use value to pay for the relayer fee on the destination chain
        IBridgeInterface(bridge).xcall{ value: msg.value }({
            destination: bridgeData.destinationDomainId, // Domain ID of the destination chain
            to: L2_REWARDS_MANAGER, // Address of the target contract
            asset: address(0), // Address of the token contract
            delegate: msg.sender, // Address that can revert or forceLocal on destination
            amount: 0, // Amount of tokens to transfer
            slippage: 0, // Max slippage the user will accept in BPS (e.g. 300 = 3%)
            callData: encodedData // Encoded data to send
         });

        emit L2RewardClaimerUpdated(msg.sender, claimer);
    }

    /**
     * @notice Mints and bridges rewards according to the provided parameters.
     * @dev Restricted access to `ROLE_ID_OPERATIONS_PAYMASTER`
     */
    function mintAndBridgeRewards(MintAndBridgeParams calldata params) external payable restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

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

        $.lastRewardMintTimestamp = uint48(block.timestamp);

        // Mint the rewards and deposit them into the lockbox
        (uint256 ethToPufETHRate, uint256 shares) = PUFFER_VAULT.mintRewards(params.rewardsAmount);
        PUFFER_VAULT.approve(address(LOCKBOX), shares);
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

        // we use value to pay for the relayer fee on the destination chain
        IBridgeInterface(params.bridge).xcall{ value: msg.value }({
            destination: bridgeData.destinationDomainId, // Domain ID of the destination chain
            to: L2_REWARDS_MANAGER, // Address of the target contract
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
     * @notice This contract receives XPufETH from the L2RewardManager via the bridge, unwraps it to pufETH and then burns the pufETH, reverting the original mintAndBridge call
     * @dev Restricted access to `ROLE_ID_BRIDGE`
     */
    function xReceive(bytes32, uint256, address, address originSender, uint32, bytes memory callData)
        external
        override(IXReceiver)
        onlyRewardsManager(originSender)
        restricted
        returns (bytes memory)
    {
        // We decode the data to get the amount of shares and the ETH amount
        L2RewardManagerStorage.EpochRecord memory epochRecord =
            abi.decode(callData, (L2RewardManagerStorage.EpochRecord));

        XPUFETH.approve(address(LOCKBOX), epochRecord.pufETHAmount);
        // get the pufETH
        LOCKBOX.withdraw(epochRecord.pufETHAmount);

        // Tell the PufferVault to burn the pufETH and subtract from the ethRewardsAmount
        // The PufferVault will subtract ethAmount from the rewardsAmount and burn the pufETH from this contract
        PUFFER_VAULT.revertMintRewards({ pufETHAmount: epochRecord.pufETHAmount, ethAmount: epochRecord.ethAmount });

        emit RevertedRewards({
            rewardsAmount: epochRecord.ethAmount,
            startEpoch: epochRecord.startEpoch,
            endEpoch: epochRecord.endEpoch,
            rewardsRoot: epochRecord.rewardRoot
        });

        return "";
    }

    /**
     * @notice Updates the bridge data.
     * @param bridge The address of the bridge.
     * @param bridgeData The updated bridge data.
     * @dev Restricted access to `ROLE_ID_DAO`
     */
    function updateBridgeData(address bridge, BridgeData memory bridgeData) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        if (bridge == address(0)) {
            revert InvalidAddress();
        }

        $.bridges[bridge].destinationDomainId = bridgeData.destinationDomainId;
        emit BridgeDataUpdated(bridge, bridgeData);
    }

    /**
     * @notice Sets the allowed reward mint amount.
     * @param newAmount The new allowed reward mint amount.
     * @dev Restricted access to `ROLE_ID_DAO`
     */
    function setAllowedRewardMintAmount(uint104 newAmount) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        emit AllowedRewardMintAmountUpdated($.allowedRewardMintAmount, newAmount);

        $.allowedRewardMintAmount = newAmount;
    }

    /**
     * @notice Sets the allowed reward mint frequency.
     * @param newFrequency The new allowed reward mint frequency.
     * @dev Restricted access to `ROLE_ID_DAO`
     */
    function setAllowedRewardMintFrequency(uint104 newFrequency) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        emit AllowedRewardMintFrequencyUpdated($.allowedRewardMintFrequency, newFrequency);

        $.allowedRewardMintFrequency = newFrequency;
    }

    /**
     * @notice Returns the bridge data for a given bridge.
     * @param bridge The address of the bridge.
     * @return The bridge data.
     */
    function getBridge(address bridge) external view returns (BridgeData memory) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        return $.bridges[bridge];
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
