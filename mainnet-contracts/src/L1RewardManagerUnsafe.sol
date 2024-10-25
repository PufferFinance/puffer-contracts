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
import { Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { IBridgeInterface } from "./interface/Connext/IBridgeInterface.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";

/**
 * @title L1RewardManagerStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract L1RewardManagerStorage {
    /**
     * @notice Parameters for setting a claimer.
     * @param account The account setting the claimer.
     * @param claimer The address of the new claimer.
     */
    struct SetClaimerParams {
        address account;
        address claimer;
    }

    /**
     * @notice Parameters for minting and bridging rewards (calldata).
     * @param rewardsAmount The amount of rewards to be bridged.
     * @param ethToPufETHRate The exchange rate from ETH to pufETH.
     * @param startEpoch The starting epoch for the rewards.
     * @param endEpoch The ending epoch for the rewards.
     * @param rewardsRoot The merkle root of the rewards.
     * @param rewardsURI The URI for the rewards metadata.
     */
    struct MintAndBridgeData {
        string rewardsURI;
        uint256 rewardsAmount;
        uint256 ethToPufETHRate;
        uint256 startEpoch;
        uint256 endEpoch;
        bytes32 rewardsRoot;
    }

    /**
     * @notice Data required for bridging.
     * @param destinationDomainId The destination domain ID.
     */
    struct BridgeData {
        // using struct to allow future addition to this
        uint32 destinationDomainId;
    }

    /**
     * @custom:storage-location erc7201:l1rewardmanager.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct RewardManagerStorage {
        uint104 allowedRewardMintAmount;
        uint48 lastRewardMintTimestamp;
        uint104 allowedRewardMintFrequency;
        mapping(address bridge => BridgeData bridgeData) bridges;
    }

    // keccak256(abi.encode(uint256(keccak256("l1rewardmanager.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _REWARD_MANAGER_STORAGE_LOCATION =
        0xb18045c429f6c4e33b477568e1a40f795629ac8937518d2b48a302e4c0fbb700;

    function _getRewardManagerStorage() internal pure returns (RewardManagerStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _REWARD_MANAGER_STORAGE_LOCATION
        }
    }
}

/**
 * @title L1RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 * @custom:oz-upgrades-from src/L1RewardManager.sol:L1RewardManager
 */
contract L1RewardManagerUnsafe is
    IXReceiver,
    IL1RewardManager,
    L1RewardManagerStorage,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    /**
     * @notice The XPUFETH token contract on Ethereum Mainnet
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IERC20 public immutable XPUFETH;
    /**
     * @notice The PufferVault contract on Ethereum Mainnet
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    PufferVaultV3 public immutable PUFFER_VAULT;
    /**
     * @notice The XERC20Lockbox contract on Ethereum Mainnet
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IXERC20Lockbox public immutable LOCKBOX;
    /**
     * @notice The Rewards Manager contract on L2
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    address public immutable L2_REWARDS_MANAGER;

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address xPufETH, address lockbox, address pufETH, address l2RewardsManager) {
        XPUFETH = IERC20(xPufETH);
        LOCKBOX = IXERC20Lockbox(lockbox);
        PUFFER_VAULT = PufferVaultV3(payable(pufETH));
        L2_REWARDS_MANAGER = l2RewardsManager;
        _disableInitializers();
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
        _setAllowedRewardMintFrequency(10 hours);
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

        // msg.value is used to pay for the relayer fee on the destination chain
        IBridgeInterface(bridge).xcall{ value: msg.value }({
            destination: bridgeData.destinationDomainId, // Domain ID of the destination chain
            to: L2_REWARDS_MANAGER, // Address of the target contract on the destination chain
            delegate: claimer, // Address that can revert on destination
            asset: address(0), // Address of the token contract
            amount: 0, // We don't transfer any tokens
            slippage: 0, // No slippage
            callData: abi.encode(
                BridgingParams({
                    bridgingType: BridgingType.SetClaimer,
                    data: abi.encode(SetClaimerParams({ account: msg.sender, claimer: claimer }))
                })
            ) // Encoded data to bridge to the target contract
         });

        emit L2RewardClaimerUpdated(msg.sender, claimer);
    }

    /**
     * @notice Mints pufETH, converts it to xPufETH and bridges it to the L2RewardsClaimer contract on L2 according to the provided parameters.
     * @dev Restricted access to `ROLE_ID_OPERATIONS_PAYMASTER`
     *
     * The bridge must be allowlisted in the contract and the amount must be less than the allowed mint amount.
     * The minting can be done at most once per allowed frequency.
     *
     * This action can be reverted by the L2RewardsClaimer contract on L2.
     * The l2RewradClaimer can revert this action by bridging back the assets to this contract (see xReceive).
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

        // Update the last mint timestamp
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

        // we use value to pay for the relayer fee on the destination chain
        IBridgeInterface(params.bridge).xcall{ value: msg.value }({
            destination: bridgeData.destinationDomainId, // Domain ID of the destination chain
            to: L2_REWARDS_MANAGER, // Address of the target contract on the destination chain
            asset: address(XPUFETH), // We are bridging xPufETH
            delegate: msg.sender, // Address that can revert or forceLocal on destination
            amount: shares, // Amount of xPufETH to bridge
            slippage: 0, // No slippage
            callData: abi.encode(
                BridgingParams({ bridgingType: BridgingType.MintAndBridge, data: abi.encode(bridgingCalldata) })
            ) // Encoded data to send
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
    function xReceive(bytes32, uint256, address, address originSender, uint32 originDomainId, bytes calldata callData)
        external
        override(IXReceiver)
        restricted
        returns (bytes memory)
    {
        // The call must originate from the L2_REWARDS_MANAGER
        if (originSender != address(L2_REWARDS_MANAGER)) {
            revert Unauthorized();
        }

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        if ($.bridges[msg.sender].destinationDomainId != originDomainId) {
            revert Unauthorized();
        }

        // We decode the data to get the amount of shares(pufETH) and the ETH amount.
        L2RewardManagerStorage.EpochRecord memory epochRecord =
            abi.decode(callData, (L2RewardManagerStorage.EpochRecord));

        XPUFETH.approve(address(LOCKBOX), epochRecord.pufETHAmount);
        // get the pufETH
        LOCKBOX.withdraw(epochRecord.pufETHAmount);

        // The PufferVault will burn the pufETH from this contract and subtract the ETH amount from the ethRewardsAmount
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
    function updateBridgeData(address bridge, BridgeData calldata bridgeData) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        if (bridge == address(0)) {
            revert InvalidAddress();
        }

        $.bridges[bridge].destinationDomainId = bridgeData.destinationDomainId;
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
        _setAllowedRewardMintFrequency(newFrequency);
    }

    function _setAllowedRewardMintFrequency(uint104 newFrequency) internal {
        if (newFrequency < 10 hours) {
            revert InvalidMintFrequency();
        }
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        emit AllowedRewardMintFrequencyUpdated($.allowedRewardMintFrequency, newFrequency);

        $.allowedRewardMintFrequency = newFrequency;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
