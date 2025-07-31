// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IL1RewardManager } from "./interface/IL1RewardManager.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { L1RewardManagerStorage } from "./L1RewardManagerStorage.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";
import { IOFT } from "./interface/LayerZero/IOFT.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

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
    using OptionsBuilder for bytes;

    /**
     * @notice The PufferVault contract on Ethereum Mainnet
     */
    PufferVaultV5 public immutable PUFFER_VAULT;

    /**
     * @notice The pufETH OFT address for singleton design
     * @dev Immutable since it is known at deployment time on L1 and cannot be changed afterwards
     */
    IOFT public immutable PUFETH_OFT;

    /**
     * @notice The Rewards Manager contract on L2
     */
    address public immutable L2_REWARDS_MANAGER;

    constructor(address pufETH, address l2RewardsManager, address pufETH_OFT) {
        if (pufETH == address(0) || l2RewardsManager == address(0)) {
            revert InvalidAddress();
        }
        PUFFER_VAULT = PufferVaultV5(payable(pufETH));
        PUFETH_OFT = IOFT(payable(pufETH_OFT));
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
    function setL2RewardClaimer(address claimer) external payable {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(50000, 0).addExecutorLzComposeOption(0, 50000, 0);

        PUFETH_OFT.send{ value: msg.value }(
            IOFT.SendParam({
                dstEid: $.destinationEID,
                to: bytes32(uint256(uint160(L2_REWARDS_MANAGER))),
                amountLD: 0,
                minAmountLD: 0,
                extraOptions: options,
                composeMsg: abi.encode(
                    BridgingParams({
                        bridgingType: BridgingType.SetClaimer,
                        data: abi.encode(SetClaimerParams({ account: msg.sender, claimer: claimer }))
                    })
                ),
                oftCmd: bytes("")
            }),
            IOFT.MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }),
            msg.sender // refundAddress
        );
        emit L2RewardClaimerUpdated(msg.sender, claimer);
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

        // Update the last mint timestamp
        $.lastRewardMintTimestamp = uint48(block.timestamp);

        // Mint the rewards and lock them into the pufETHAdapter to be bridged to L2
        (uint256 ethToPufETHRate, uint256 shares) = PUFFER_VAULT.mintRewards(params.rewardsAmount);

        PUFFER_VAULT.approve(address(PUFETH_OFT), shares);

        MintAndBridgeData memory bridgingCalldata = MintAndBridgeData({
            rewardsAmount: params.rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: params.startEpoch,
            endEpoch: params.endEpoch,
            rewardsRoot: params.rewardsRoot,
            rewardsURI: params.rewardsURI
        });

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50000, 0) // Gas for lzReceive
            .addExecutorLzComposeOption(0, 50000, 0); // Gas for lzCompose

        PUFETH_OFT.send{ value: msg.value }(
            IOFT.SendParam({
                dstEid: $.destinationEID,
                to: bytes32(uint256(uint160(L2_REWARDS_MANAGER))),
                amountLD: shares,
                minAmountLD: 0,
                extraOptions: options,
                composeMsg: abi.encode(
                    BridgingParams({ bridgingType: BridgingType.MintAndBridge, data: abi.encode(bridgingCalldata) })
                ),
                oftCmd: bytes("")
            }),
            IOFT.MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }),
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
     * @notice Handles incoming composed messages from LayerZero Endpoint on L1
     * @notice Revert the original mintAndBridge call
     * @dev Ensures the message comes from the correct OApp and is sent through the authorized endpoint.
     * @dev Restricted to the LayerZero Endpoint contract on L1
     *
     * @param oft The address of the pufETH OFTAdapter that is sending the composed message.
     * @param message The calldata received from L2RewardManager.
     */
    function lzCompose(
        address oft,
        bytes32, /* _guid */
        bytes calldata message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) external payable override restricted {
        // Ensure that only the whitelisted pufETH OFT can call this function
        if (oft != address(PUFETH_OFT)) {
            revert Unauthorized();
        }

        // Decode the OFT compose message to extract the original sender and validate authenticity
        bytes32 composeFrom = OFTComposeMsgCodec.composeFrom(message);
        bytes memory actualMessage = OFTComposeMsgCodec.composeMsg(message);

        // Validate that the original sender is our legitimate L2RewardManager
        address originalSender = address(uint160(uint256(composeFrom)));
        if (originalSender != L2_REWARDS_MANAGER) {
            revert Unauthorized();
        }

        // We decode the actual message to get the amount of shares(pufETH) and the ETH amount.
        L2RewardManagerStorage.EpochRecord memory epochRecord =
            abi.decode(actualMessage, (L2RewardManagerStorage.EpochRecord));

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
     * @notice Sets the destination endpoint ID
     * @param newDestinationEID The new destination endpoint ID
     */
    function setDestinationEID(uint32 newDestinationEID) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        emit DestinationEIDUpdated({ oldDestinationEID: $.destinationEID, newDestinationEID: newDestinationEID });
        $.destinationEID = newDestinationEID;
    }

    /**
     * @notice Returns the destination endpoint ID
     */
    function getDestinationEID() external view returns (uint32) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.destinationEID;
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
