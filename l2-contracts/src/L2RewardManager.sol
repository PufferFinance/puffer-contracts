// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IL2RewardManager } from "./interface/IL2RewardManager.sol";
import { L2RewardManagerStorage } from "./L2RewardManagerStorage.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { IL1RewardManager } from "mainnet-contracts/src/interface/IL1RewardManager.sol";
import { InvalidAddress } from "mainnet-contracts/src/Errors.sol";
import { L1RewardManagerStorage } from "mainnet-contracts/src/L1RewardManagerStorage.sol";
import { IOFT } from "mainnet-contracts/src/interface/LayerZero/IOFT.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

// Unified interface for pufETH OFT that provides both ERC20 and LayerZero OFT functionality
interface IPufETH is IOFT, IERC20 { }

/**
 * @title L2RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract L2RewardManager is
    IL2RewardManager,
    L2RewardManagerStorage,
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    IOAppComposer
{
    /**
     * @notice The rewards manager contract on L1
     */
    address public immutable L1_REWARD_MANAGER;

    constructor(address l1RewardManager) {
        if (l1RewardManager == address(0)) {
            revert InvalidAddress();
        }
        L1_REWARD_MANAGER = l1RewardManager;
        _disableInitializers();
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
        _setClaimingDelay(12 hours);
    }

    /**
     * @inheritdoc IL2RewardManager
     * @dev Restricted in this context is like the `whenNotPaused` modifier from Pausable.sol
     */
    function claimRewards(ClaimOrder[] calldata claimOrders) external restricted {
        for (uint256 i = 0; i < claimOrders.length; ++i) {
            if (isClaimed(claimOrders[i].intervalId, claimOrders[i].account)) {
                revert AlreadyClaimed(claimOrders[i].intervalId, claimOrders[i].account);
            }

            RewardManagerStorage storage $ = _getRewardManagerStorage();

            // L1 contracts MUST set the claimer
            address recipient = $.rewardsClaimers[claimOrders[i].account];
            if (claimOrders[i].isL1Contract && recipient == address(0)) {
                revert ClaimerNotSet(claimOrders[i].account);
            }

            EpochRecord storage epochRecord = $.epochRecords[claimOrders[i].intervalId];

            if (epochRecord.rewardRoot == bytes32(0)) {
                revert InvalidClaimingInterval(claimOrders[i].intervalId);
            }

            if (_isClaimingLocked(claimOrders[i].intervalId)) {
                revert ClaimingLocked({
                    intervalId: claimOrders[i].intervalId,
                    account: claimOrders[i].account,
                    lockedUntil: epochRecord.timeBridged + $.claimingDelay
                });
            }

            // Alice may run many Puffer validators in the same interval `totalETHEarned = sum(aliceValidators)`
            // The leaf is: keccak256(abi.encode(AliceAddress, isL1Contract, totalETHEarned))
            bytes32 leaf = keccak256(
                bytes.concat(
                    keccak256(abi.encode(claimOrders[i].account, claimOrders[i].isL1Contract, claimOrders[i].amount))
                )
            );
            if (!MerkleProof.verifyCalldata(claimOrders[i].merkleProof, epochRecord.rewardRoot, leaf)) {
                revert InvalidProof();
            }

            // Mark it claimed and transfer the tokens
            $.claimedRewards[claimOrders[i].intervalId][claimOrders[i].account] = true;

            uint256 amountToTransfer = (claimOrders[i].amount * epochRecord.ethToPufETHRate) / 1 ether;

            recipient = recipient == address(0) ? claimOrders[i].account : recipient;

            // if the custom claimer is set, then transfer the tokens to the set claimer
            // First we transfer any remaining xPufETH in this contract to the recipient
            if ($.xPufETH != address(0)) {
                uint256 xPufETHBalance = IERC20($.xPufETH).balanceOf(address(this));
                if (xPufETHBalance > 0) {
                    if (xPufETHBalance >= amountToTransfer) {
                        IERC20($.xPufETH).transfer(recipient, amountToTransfer);
                    } else {
                        IERC20($.xPufETH).transfer(recipient, xPufETHBalance);
                        IPufETH($.pufETHOFT).transfer(recipient, amountToTransfer - xPufETHBalance);
                    }
                } else {
                    IPufETH($.pufETHOFT).transfer(recipient, amountToTransfer);
                }
            } else {
                IPufETH($.pufETHOFT).transfer(recipient, amountToTransfer);
            }

            emit Claimed({
                recipient: recipient,
                account: claimOrders[i].account,
                intervalId: claimOrders[i].intervalId,
                amount: amountToTransfer
            });
        }
    }

    /**
     * @notice Handles incoming composed messages from LayerZero Endpoint on L2
     * @notice Receives the pufETH from L1 and the bridging data from the L1 Reward Manager
     * @dev Ensures the message comes from the correct OApp (pufETH OFT) and is sent through the authorized endpoint.
     * @dev Restricted to the LayerZero Endpoint contract on L2
     * @param oft The address of the oft (pufETH OFT) on L2
     * @param message The calldata received from L1RewardManager
     */
    function lzCompose(
        address oft,
        bytes32, /* _guid */
        bytes calldata message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) external payable override restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        // Ensure that only the whitelisted pufETH OFT can call this function
        if (oft != $.pufETHOFT) {
            revert Unauthorized();
        }

        // Decode the OFT compose message to extract the original sender, amount and the actual message
        bytes32 composeFrom = OFTComposeMsgCodec.composeFrom(message);
        bytes memory actualMessage = OFTComposeMsgCodec.composeMsg(message);
        uint256 amount = OFTComposeMsgCodec.amountLD(message);

        // Validate that the original sender is our legitimate L1RewardManager
        address originalSender = address(uint160(uint256(composeFrom)));
        if (originalSender != L1_REWARD_MANAGER) {
            revert Unauthorized();
        }

        // Decode the actual message to get the bridging parameters
        IL1RewardManager.BridgingParams memory bridgingParams =
            abi.decode(actualMessage, (IL1RewardManager.BridgingParams));

        if (bridgingParams.bridgingType == IL1RewardManager.BridgingType.MintAndBridge) {
            _handleMintAndBridge(amount, bridgingParams.data);
        } else if (bridgingParams.bridgingType == IL1RewardManager.BridgingType.SetClaimer) {
            _handleSetClaimer(bridgingParams.data);
        }
    }

    /**
     * @notice Freezes the claiming and reverts the bridging for the interval
     * @dev If the function is called and the bridging reverts, we can just freeze the interval and prevent any the claiming of the rewards
     * by calling `freezeClaimingForInterval`.
     *
     * In order to freeze the claiming for the interval, the interval must be locked.
     *
     * revertInterval is called to bridge the xPufETH back to the L1.
     * On the L1, we unwrap xPufETH -> pufETH and burn the pufETH to undo the minting and bridging of the rewards.
     *
     * msg.value is used to pay for the relayer fee on the destination chain.
     */
    function freezeAndRevertInterval(uint256 startEpoch, uint256 endEpoch) external payable restricted {
        _freezeClaimingForInterval(startEpoch, endEpoch);

        _revertInterval(startEpoch, endEpoch);
    }

    /**
     * @notice Freezes the claiming for the interval
     * @dev In order to freeze the claiming for the interval, the interval must be locked
     */
    function freezeClaimingForInterval(uint256 startEpoch, uint256 endEpoch) public restricted {
        _freezeClaimingForInterval(startEpoch, endEpoch);
    }

    /**
     * @notice Reverts the already frozen interval. It bridges the pufETH back to the L1
     * @dev On the L1, we burn the pufETH to undo the minting
     * We use msg.value to pay for the relayer fee on the destination chain.
     */
    function revertInterval(uint256 startEpoch, uint256 endEpoch) external payable restricted {
        _revertInterval(startEpoch, endEpoch);
    }

    /**
     * @notice Sets the delay period for claiming rewards
     * @param delayPeriod The new delay period in seconds
     */
    function setDelayPeriod(uint256 delayPeriod) external restricted {
        _setClaimingDelay(delayPeriod);
    }

    /**
     * @notice Sets the address of the old pufETH token
     * @dev If set to Zero address, means that the old pufETH token is not used anymore
     * @param xPufETH The address of the old pufETH token
     */
    function setXPufETH(address xPufETH) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        $.xPufETH = xPufETH;
    }

    /**
     * @notice Sets the pufETH OFT address
     * @param newPufETHOFT The new pufETH OFT address
     */
    function setPufETHOFT(address newPufETHOFT) external restricted {
        if (newPufETHOFT == address(0)) {
            revert InvalidAddress();
        }
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        address oldPufETHOFT = $.pufETHOFT;
        $.pufETHOFT = newPufETHOFT;
        emit PufETHOFTUpdated({ oldPufETHOFT: oldPufETHOFT, newPufETHOFT: newPufETHOFT });
    }

    /**
     * @notice Sets the destination endpoint ID
     * @param newDestinationEID The new destination endpoint ID
     */
    function setDestinationEID(uint32 newDestinationEID) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        uint32 oldDestinationEID = $.destinationEID;
        $.destinationEID = newDestinationEID;
        emit DestinationEIDUpdated({ oldDestinationEID: oldDestinationEID, newDestinationEID: newDestinationEID });
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getIntervalId(uint256 startEpoch, uint256 endEpoch) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(startEpoch, endEpoch));
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function isClaimingLocked(bytes32 intervalId) external view returns (bool) {
        return _isClaimingLocked(intervalId);
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function isClaimed(bytes32 intervalId, address account) public view returns (bool) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimedRewards[intervalId][account];
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getEpochRecord(bytes32 intervalId) external view returns (EpochRecord memory) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.epochRecords[intervalId];
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getRewardsClaimer(address account) public view returns (address) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.rewardsClaimers[account];
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getClaimingDelay() external view returns (uint256) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimingDelay;
    }
    /**
     * @inheritdoc IL2RewardManager
     */

    function getXPufETH() external view returns (address) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.xPufETH;
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getPufETHOFT() external view returns (address) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.pufETHOFT;
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getDestinationEID() external view returns (uint32) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.destinationEID;
    }

    function _handleMintAndBridge(uint256 amount, bytes memory data) internal {
        L1RewardManagerStorage.MintAndBridgeData memory params =
            abi.decode(data, (L1RewardManagerStorage.MintAndBridgeData));

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        bytes32 intervalId = getIntervalId(params.startEpoch, params.endEpoch);

        $.epochRecords[intervalId] = EpochRecord({
            ethToPufETHRate: params.ethToPufETHRate,
            startEpoch: uint104(params.startEpoch),
            endEpoch: uint104(params.endEpoch),
            timeBridged: uint48(block.timestamp),
            rewardRoot: params.rewardsRoot,
            pufETHAmount: uint128(amount),
            ethAmount: uint128(params.rewardsAmount)
        });

        emit RewardRootAndRatePosted({
            rewardsAmount: params.rewardsAmount,
            ethToPufETHRate: params.ethToPufETHRate,
            startEpoch: params.startEpoch,
            intervalId: intervalId,
            endEpoch: params.endEpoch,
            rewardsRoot: params.rewardsRoot
        });
    }

    /**
     * @dev We want to allow Smart Contracts(Node Operators) on Ethereum Mainnet to set the claimer of the rewards on L2. It is likely that they will not have the same address on L2.
     */
    function _handleSetClaimer(bytes memory data) internal {
        L1RewardManagerStorage.SetClaimerParams memory claimerParams =
            abi.decode(data, (L1RewardManagerStorage.SetClaimerParams));

        RewardManagerStorage storage $ = _getRewardManagerStorage();
        $.rewardsClaimers[claimerParams.account] = claimerParams.claimer;

        emit ClaimerSet({ account: claimerParams.account, claimer: claimerParams.claimer });
    }

    function _setClaimingDelay(uint256 newDelay) internal {
        if (newDelay < 6 hours) {
            revert InvalidDelayPeriod();
        }
        if (newDelay > 12 hours) {
            revert InvalidDelayPeriod();
        }
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        emit ClaimingDelayChanged({ oldDelay: $.claimingDelay, newDelay: newDelay });
        $.claimingDelay = newDelay;
    }

    function _isClaimingLocked(bytes32 intervalId) internal view returns (bool) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        uint256 timeBridged = $.epochRecords[intervalId].timeBridged;

        // If the timeBridged is 0, the interval is either reverted, or has not been bridged yet
        // we consider that the claiming is locked in both cases
        if (timeBridged == 0) {
            return true;
        }

        return block.timestamp < timeBridged + $.claimingDelay;
    }

    function _freezeClaimingForInterval(uint256 startEpoch, uint256 endEpoch) internal {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        bytes32 intervalId = getIntervalId(startEpoch, endEpoch);

        // Revert if the claiming is not locked
        if (!_isClaimingLocked(intervalId)) {
            revert UnableToFreezeInterval();
        }

        // revert for non-existing interval
        if ($.epochRecords[intervalId].rewardRoot == bytes32(0)) {
            revert UnableToFreezeInterval();
        }

        // To freeze the claiming, we set the timeBridged to 0
        $.epochRecords[intervalId].timeBridged = 0;

        emit ClaimingIntervalFrozen({ startEpoch: startEpoch, endEpoch: endEpoch });
    }

    /**
     * @notice Reverts the already frozen interval
     */
    function _revertInterval(uint256 startEpoch, uint256 endEpoch) internal {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        bytes32 intervalId = getIntervalId(startEpoch, endEpoch);

        EpochRecord memory epochRecord = $.epochRecords[intervalId];

        // We only want to revert the frozen intervals, if the interval is not frozen, we revert
        if (epochRecord.timeBridged != 0 && epochRecord.rewardRoot != bytes32(0)) {
            revert UnableToRevertInterval();
        }

        if (epochRecord.rewardRoot == bytes32(0)) {
            revert UnableToRevertInterval();
        }

        // We bridge the pufETH back to the L1
        // We don't need to approve since the oft is itself the pufETH token
        IPufETH($.pufETHOFT).send{ value: msg.value }(
            IOFT.SendParam({
                dstEid: $.destinationEID,
                to: bytes32(uint256(uint160(L1_REWARD_MANAGER))),
                amountLD: epochRecord.pufETHAmount,
                minAmountLD: 0,
                extraOptions: bytes(""),
                composeMsg: abi.encode(epochRecord),
                oftCmd: bytes("")
            }),
            IOFT.MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }),
            msg.sender // refundAddress
        );

        delete $.epochRecords[intervalId];

        emit ClaimingIntervalReverted({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            intervalId: intervalId,
            pufETHAmount: epochRecord.pufETHAmount,
            rewardsRoot: epochRecord.rewardRoot
        });
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    // slither-disable-next-line dead-code
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
