// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IL2RewardManager } from "./interface/IL2RewardManager.sol";
import { L2RewardManagerStorage } from "./L2RewardManagerStorage.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { InvalidAmount, Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { IL1RewardManager } from "mainnet-contracts/src/interface/IL1RewardManager.sol";
import { InvalidAddress } from "mainnet-contracts/src/Errors.sol";
import { L1RewardManagerStorage } from "mainnet-contracts/src/L1RewardManagerStorage.sol";
import { IOApp } from "mainnet-contracts/src/interface/LayerZero/IOApp.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";

// We need to extend the IOApp interface to include the IERC20 interface
interface IPufETH is IOApp, IERC20 { }

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
     * @notice pufETH OFT token on this chain
     */
    IPufETH public immutable PUFETH;

    /**
     * @notice The rewards manager contract on L1
     */
    address public immutable L1_REWARD_MANAGER;

    constructor(address oft, address l1RewardManager) {
        PUFETH = IPufETH(oft); // TODO: DO we really need this? We can use the oft directly
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

            //TODO: we have XPUFTH in this contract from previous transfer, so how do we handle this?
            // shall we use something like?:
            // if (IERC20(XPUFETH).balanceOf(address(this)) > amountToTransfer) {
            //     IERC20(XPUFETH).transfer(recipient, amountToTransfer);
            // } else {
            //     PUFETH.transfer(recipient, amountToTransfer);
            // }

            // TODO: Should we use the oft here? we need to take oft address as a parameter then
            PUFETH.transfer(recipient, amountToTransfer);

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
     * @param oft The address of the oft (pufETH OFT) on L2
     * @param message The calldata received from L1RewardManager.
     */
    function lzCompose(
        address oft,
        bytes32, /* _guid */
        bytes calldata message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) external payable override {
        if (oft != address(PUFETH)) {
            revert Unauthorized();
        }

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        if (msg.sender != $.bridges[oft].endpoint) {
            revert Unauthorized();
        }

        IL1RewardManager.BridgingParams memory bridgingParams = abi.decode(message, (IL1RewardManager.BridgingParams));

        if (bridgingParams.bridgingType == IL1RewardManager.BridgingType.MintAndBridge) {
            _handleMintAndBridge(bridgingParams.data);
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
    function freezeAndRevertInterval(address bridge, uint256 startEpoch, uint256 endEpoch)
        external
        payable
        restricted
    {
        _freezeClaimingForInterval(startEpoch, endEpoch);

        _revertInterval(bridge, startEpoch, endEpoch);
    }

    /**
     * @notice Freezes the claiming for the interval
     * @dev In order to freeze the claiming for the interval, the interval must be locked
     */
    function freezeClaimingForInterval(uint256 startEpoch, uint256 endEpoch) public restricted {
        _freezeClaimingForInterval(startEpoch, endEpoch);
    }

    /**
     * @notice Reverts the already frozen interval. It bridges the xPufETH back to the L1
     * @dev On the L1, we unwrap xPufETH to pufETH and burn the pufETH to undo the minting
     * We use msg.value to pay for the relayer fee on the destination chain.
     */
    function revertInterval(address bridge, uint256 startEpoch, uint256 endEpoch) external payable restricted {
        _revertInterval(bridge, startEpoch, endEpoch);
    }

    /**
     * @notice Updates the bridge data.
     * @param oft The address of the oft.
     * @param bridgeData The updated bridge data.
     */
    function updateBridgeData(address oft, BridgeData memory bridgeData) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        if (oft == address(0)) {
            revert InvalidAddress();
        }

        $.bridges[oft].destinationDomainId = bridgeData.destinationDomainId;
        $.bridges[oft].endpoint = bridgeData.endpoint;
        emit BridgeDataUpdated(oft, bridgeData);
    }

    /**
     * @notice Sets the delay period for claiming rewards
     * @param delayPeriod The new delay period in seconds
     */
    function setDelayPeriod(uint256 delayPeriod) external restricted {
        _setClaimingDelay(delayPeriod);
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

    function _handleMintAndBridge(bytes memory data) internal {
        L1RewardManagerStorage.MintAndBridgeData memory params =
            abi.decode(data, (L1RewardManagerStorage.MintAndBridgeData));

        // TODO: we can't do this check since we don't get the amount in the lzCompose call, we have to get it from the calldata
        // Sanity check
        // if (amount != ((params.rewardsAmount * params.ethToPufETHRate) / 1 ether)) {
        //     revert InvalidAmount();
        // }

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        bytes32 intervalId = getIntervalId(params.startEpoch, params.endEpoch);

        $.epochRecords[intervalId] = EpochRecord({
            ethToPufETHRate: params.ethToPufETHRate,
            startEpoch: uint104(params.startEpoch),
            endEpoch: uint104(params.endEpoch),
            timeBridged: uint48(block.timestamp),
            rewardRoot: params.rewardsRoot,
            pufETHAmount: uint128(params.pufETHAmount),
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
    function _revertInterval(address oft, uint256 startEpoch, uint256 endEpoch) internal {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        BridgeData memory bridgeData = $.bridges[oft];

        if (bridgeData.destinationDomainId == 0) {
            revert BridgeNotAllowlisted();
        }

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
        IPufETH(oft).send{ value: msg.value }(
            IOApp.SendParam({
                dstEid: bridgeData.destinationDomainId,
                to: bytes32(uint256(uint160(L1_REWARD_MANAGER))),
                amountLD: epochRecord.pufETHAmount,
                minAmountLD: 0,
                extraOptions: bytes(""),
                composeMsg: abi.encode(epochRecord),
                oftCmd: bytes("")
            }),
            IOApp.MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }),
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
