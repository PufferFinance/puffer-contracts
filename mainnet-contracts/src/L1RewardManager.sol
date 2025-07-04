// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
// import { IXReceiver } from "@connext/interfaces/core/IXReceiver.sol";
// import { IXERC20Lockbox } from "./interface/IXERC20Lockbox.sol";
import { IL1RewardManager } from "./interface/IL1RewardManager.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { L1RewardManagerStorage } from "./L1RewardManagerStorage.sol";
// import { IBridgeInterface } from "./interface/Connext/IBridgeInterface.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";
import { IOApp } from "./interface/LayerZero/IOApp.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";

/**
 * @title L1RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract L1RewardManager is
    IL1RewardManager,
    L1RewardManagerStorage,
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    IOAppComposer
{
    /**
     * @notice The pufETH OFTAdapter contract on Ethereum Mainnet
     */
    IOApp public immutable PUFETH_ADAPTER;

    /**
     * @notice The PufferVault contract on Ethereum Mainnet
     */
    PufferVaultV5 public immutable PUFFER_VAULT;
    /**
     * @notice The Rewards Manager contract on L2
     */
    address public immutable L2_REWARDS_MANAGER;

    constructor(address pufETHAdapter, address pufETH, address l2RewardsManager) {
        PUFETH_ADAPTER = IOApp(pufETHAdapter);
        PUFFER_VAULT = PufferVaultV5(payable(pufETH));
        L2_REWARDS_MANAGER = l2RewardsManager;
        _disableInitializers();
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
        _setAllowedRewardMintFrequency(20 hours);
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function setL2RewardClaimer(address oft, address claimer) external payable {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        BridgeData memory bridgeData = $.bridges[oft];
        if (bridgeData.destinationDomainId == 0) {
            revert BridgeNotAllowlisted();
        }

        PUFETH_ADAPTER.send{ value: msg.value }(
            IOApp.SendParam({
                dstEid: bridgeData.destinationDomainId,
                to: bytes32(uint256(uint160(L2_REWARDS_MANAGER))),
                amountLD: 0,
                minAmountLD: 0,
                extraOptions: bytes(""),
                composeMsg: abi.encode(
                    BridgingParams({
                        bridgingType: BridgingType.SetClaimer,
                        data: abi.encode(SetClaimerParams({ account: msg.sender, claimer: claimer }))
                    })
                ),
                oftCmd: bytes("")
            }),
            IOApp.MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }),
            msg.sender // refundAddress
        );
    }

    /**
     * @notice Mints pufETH, locks into the pufETHAdapter and bridges it to the L2RewardManager contract on L2 according to the provided parameters.
     * @dev Restricted access to `ROLE_ID_OPERATIONS_PAYMASTER`
     *
     * The oft must be allowlisted in the contract and the amount must be less than the allowed mint amount.
     * The minting can be done at most once per allowed frequency.
     *
     * This action can be reverted by the L2RewardManager contract on L2.
     * The L2RewardManager can revert this action by bridging back the assets to this contract (see lzCompose).
     */
    function mintAndBridgeRewards(MintAndBridgeParams calldata params) external payable restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        if (params.rewardsAmount > $.allowedRewardMintAmount) {
            revert InvalidMintAmount();
        }

        if (($.lastRewardMintTimestamp + $.allowedRewardMintFrequency) > block.timestamp) {
            revert NotAllowedMintFrequency();
        }

        BridgeData memory bridgeData = $.bridges[params.oft];
        if (bridgeData.destinationDomainId == 0) {
            revert BridgeNotAllowlisted();
        }

        // Update the last mint timestamp
        $.lastRewardMintTimestamp = uint48(block.timestamp);

        // Mint the rewards and deposit them into the lockbox
        (uint256 ethToPufETHRate, uint256 shares) = PUFFER_VAULT.mintRewards(params.rewardsAmount);

        PUFFER_VAULT.approve(params.oft, shares);

        MintAndBridgeData memory bridgingCalldata = MintAndBridgeData({
            rewardsAmount: params.rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: params.startEpoch,
            endEpoch: params.endEpoch,
            rewardsRoot: params.rewardsRoot,
            rewardsURI: params.rewardsURI
        });

        PUFETH_ADAPTER.send{ value: msg.value }(
            IOApp.SendParam({
                dstEid: bridgeData.destinationDomainId,
                to: bytes32(uint256(uint160(L2_REWARDS_MANAGER))),
                amountLD: shares,
                minAmountLD: 0,
                extraOptions: bytes(""),
                composeMsg: abi.encode(
                    BridgingParams({ bridgingType: BridgingType.MintAndBridge, data: abi.encode(bridgingCalldata) })
                ),
                oftCmd: bytes("")
            }),
            IOApp.MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }),
            msg.sender // refundAddress
        );

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
     * @notice Handles incoming composed messages from LayerZero
     * @notice Revert the original mintAndBridge call
     * @dev Ensures the message comes from the correct OApp and is sent through the authorized endpoint.
     *
     * @param pufETHAdapter The address of the pufETH OFTAdapter that is sending the composed message.
     */
    function lzCompose(
        address pufETHAdapter,
        bytes32, /* _guid */
        bytes calldata message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) external payable override {
        if (pufETHAdapter != address(PUFETH_ADAPTER)) {
            revert Unauthorized();
        }
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        if (msg.sender != $.bridges[pufETHAdapter].endpoint) {
            revert Unauthorized();
        }
        // We decode the data to get the amount of shares(pufETH) and the ETH amount.
        L2RewardManagerStorage.EpochRecord memory epochRecord =
            abi.decode(message, (L2RewardManagerStorage.EpochRecord));

        // This contract has already received the pufETH from pufETHAdapter after bridging back to L1
        // The PufferVault will burn the pufETH from this contract and subtract the ETH amount from the ethRewardsAmount
        PUFFER_VAULT.revertMintRewards({ pufETHAmount: epochRecord.pufETHAmount, ethAmount: epochRecord.ethAmount });

        // We emit the event to the L1RewardManager contract
        emit RevertedRewards({
            rewardsAmount: epochRecord.ethAmount,
            startEpoch: epochRecord.startEpoch,
            endEpoch: epochRecord.endEpoch,
            rewardsRoot: epochRecord.rewardRoot
        });
    }
    /**
     * @notice Updates the bridge data.
     * @param oft The address of the oft.
     * @param bridgeData The updated bridge data.
     * @dev Restricted access to `ROLE_ID_DAO`
     */

    function updateBridgeData(address oft, BridgeData calldata bridgeData) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        if (oft == address(0)) {
            revert InvalidAddress();
        }

        $.bridges[oft].destinationDomainId = bridgeData.destinationDomainId;
        $.bridges[oft].endpoint = bridgeData.endpoint;
        emit BridgeDataUpdated(oft, bridgeData);
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

    /**
     * @notice Returns the bridge data for a given oft.
     * @param oft The address of the oft.
     * @return The bridge data.
     */
    function getBridge(address oft) external view returns (BridgeData memory) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        return $.bridges[oft];
    }

    function _setAllowedRewardMintFrequency(uint104 newFrequency) internal {
        if (newFrequency < 20 hours) {
            revert InvalidMintFrequency();
        }
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        emit AllowedRewardMintFrequencyUpdated($.allowedRewardMintFrequency, newFrequency);

        $.allowedRewardMintFrequency = newFrequency;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
