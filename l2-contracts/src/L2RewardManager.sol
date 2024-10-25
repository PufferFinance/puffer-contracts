// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IL2RewardManager } from "./interface/IL2RewardManager.sol";
import { IXReceiver } from "@connext/interfaces/core/IXReceiver.sol";
import { L2RewardManagerStorage } from "./L2RewardManagerStorage.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { InvalidAmount, Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { IBridgeInterface } from "mainnet-contracts/src/interface/Connext/IBridgeInterface.sol";
import { IL1RewardManager } from "mainnet-contracts/src/interface/IL1RewardManager.sol";
import { InvalidAddress } from "mainnet-contracts/src/Errors.sol";
import { L1RewardManagerStorage } from "mainnet-contracts/src/L1RewardManagerStorage.sol";

/**
 * @title L2RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract L2RewardManager is
    IL2RewardManager,
    L2RewardManagerStorage,
    IXReceiver,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    /**
     * @notice xPufETH token on this chain
     */
    IERC20 public immutable XPUFETH;

    /**
     * @notice Burner contract on Ethereum Mainnet
     */
    address public immutable L1_REWARD_MANAGER;

    constructor(address xPufETH, address l1RewardManager) {
        XPUFETH = IERC20(xPufETH);
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
            XPUFETH.transfer(recipient, amountToTransfer);

            emit Claimed({
                recipient: recipient,
                account: claimOrders[i].account,
                intervalId: claimOrders[i].intervalId,
                amount: amountToTransfer
            });
        }
    }

    /**
     * @notice Receives the xPufETH from L1 and the bridging data from the L1 Reward Manager
     * @dev Restricted access to `ROLE_ID_BRIDGE`
     */
    function xReceive(
        bytes32,
        uint256 amount,
        address,
        address originSender,
        uint32 originDomainId,
        bytes memory callData
    ) external override(IXReceiver) restricted returns (bytes memory) {
        if (originSender != address(L1_REWARD_MANAGER)) {
            revert Unauthorized();
        }

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        if ($.bridges[msg.sender].destinationDomainId != originDomainId) {
            revert Unauthorized();
        }

        IL1RewardManager.BridgingParams memory bridgingParams = abi.decode(callData, (IL1RewardManager.BridgingParams));

        if (bridgingParams.bridgingType == IL1RewardManager.BridgingType.MintAndBridge) {
            _handleMintAndBridge(amount, bridgingParams.data);
        } else if (bridgingParams.bridgingType == IL1RewardManager.BridgingType.SetClaimer) {
            _handleSetClaimer(bridgingParams.data);
        }
        // Return empty data
        return "";
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
     * @param bridge The address of the bridge.
     * @param bridgeData The updated bridge data.
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

    function _handleMintAndBridge(uint256 amount, bytes memory data) internal {
        L1RewardManagerStorage.MintAndBridgeData memory params =
            abi.decode(data, (L1RewardManagerStorage.MintAndBridgeData));

        // Sanity check
        if (amount != ((params.rewardsAmount * params.ethToPufETHRate) / 1 ether)) {
            revert InvalidAmount();
        }

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
    function _revertInterval(address bridge, uint256 startEpoch, uint256 endEpoch) internal {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        BridgeData memory bridgeData = $.bridges[bridge];

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

        XPUFETH.approve(bridge, epochRecord.pufETHAmount);

        IBridgeInterface(bridge).xcall{ value: msg.value }({
            destination: bridgeData.destinationDomainId, // Domain ID of the destination chain
            to: L1_REWARD_MANAGER, // Address of the target contract
            asset: address(XPUFETH), // Address of the token contract
            delegate: msg.sender, // Address that can revert or forceLocal on destination
            amount: epochRecord.pufETHAmount, // Amount of tokens to transfer
            slippage: 0, // Max slippage the user will accept in BPS (e.g. 300 = 3%)
            callData: abi.encode(epochRecord) // Encoded data to send
         });

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
