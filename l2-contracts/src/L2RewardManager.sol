// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IPufferVaultV3 } from "mainnet-contracts/src/interface/IPufferVaultV3.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IL2RewardManager } from "./interface/IL2RewardManager.sol";
import { IXReceiver } from "@connext/interfaces/core/IXReceiver.sol";
import { L2RewardManagerStorage } from "./L2RewardManagerStorage.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { InvalidAmount, Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { IBridgeInterface } from "mainnet-contracts/src/interface/Connext/IBridgeInterface.sol";
import { InvalidAddress } from "mainnet-contracts/src/Errors.sol";

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
    using SafeERC20 for IERC20;

    /**
     * @notice xPufETH token on this chain
     */
    IERC20 public immutable XPUFETH;

    /**
     * @notice PufferVault on Ethereum Mainnet
     */
    address public immutable L1_PUFFER_VAULT;

    /**
     * @notice Burner contract on Ethereum Mainnet
     */
    address public immutable L1_BURNER;

    constructor(address xPufETH, address l1PufferVault, address l1Burner) {
        XPUFETH = IERC20(xPufETH);
        L1_PUFFER_VAULT = l1PufferVault;
        L1_BURNER = l1Burner;
        _disableInitializers();
    }

    modifier onlyPufferVault(address originSender) {
        if (originSender != address(L1_PUFFER_VAULT)) {
            revert Unauthorized();
        }
        _;
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
        _setClaimingDelay(12 hours);
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function xReceive(bytes32, uint256 amount, address, address originSender, uint32, bytes memory callData)
        external
        override(IL2RewardManager, IXReceiver)
        onlyPufferVault(originSender)
        restricted
        returns (bytes memory emptyReturnData)
    {
        IPufferVaultV3.BridgingParams memory bridgingParams = abi.decode(callData, (IPufferVaultV3.BridgingParams));

        if (bridgingParams.bridgingType == IPufferVaultV3.BridgingType.MintAndBridge) {
            _handleMintAndBridge(amount, bridgingParams.data);
        } else if (bridgingParams.bridgingType == IPufferVaultV3.BridgingType.SetClaimer) {
            _handleSetClaimer(bridgingParams.data);
        } else {
            revert InvalidBridgingType();
        }

        // Return empty bytes
        return "";
    }

    /**
     * @inheritdoc IL2RewardManager
     * @dev Restricted in this context is like the `whenNotPaused` modifier from Pausable.sol
     */
    function claimRewards(ClaimOrder[] calldata claimOrders) external restricted {
        for (uint256 i = 0; i < claimOrders.length; i++) {
            if (isClaimed(claimOrders[i].startEpoch, claimOrders[i].endEpoch, claimOrders[i].account)) {
                revert AlreadyClaimed(claimOrders[i].startEpoch, claimOrders[i].endEpoch, claimOrders[i].account);
            }

            RewardManagerStorage storage $ = _getRewardManagerStorage();

            bytes32 intervalId = getIntervalId(claimOrders[i].startEpoch, claimOrders[i].endEpoch);

            EpochRecord storage epochRecord = $.epochRecords[intervalId];

            if (_isClaimingLocked(intervalId)) {
                revert ClaimingLocked({
                    startEpoch: claimOrders[i].startEpoch,
                    endEpoch: claimOrders[i].endEpoch,
                    account: claimOrders[i].account,
                    lockedUntil: epochRecord.timeBridged + $.claimingDelay
                });
            }

            // Alice may run many Puffer validators in the same interval `totalETHEarned = sum(aliceValidators)`
            // The leaf is: keccak256(abi.encode(AliceAddress, startEpoch, endEpoch, totalETHEarned))
            bytes32 leaf = keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(
                            claimOrders[i].account,
                            claimOrders[i].startEpoch,
                            claimOrders[i].endEpoch,
                            claimOrders[i].amount
                        )
                    )
                )
            );
            if (!MerkleProof.verifyCalldata(claimOrders[i].merkleProof, epochRecord.rewardRoot, leaf)) {
                revert InvalidProof();
            }

            // Mark it claimed and transfer the tokens
            $.claimedRewards[intervalId][claimOrders[i].account] = true;

            uint256 amountToTransfer = claimOrders[i].amount * epochRecord.ethToPufETHRate / 1 ether;

            address recipient = getRewardsClaimer(claimOrders[i].account);

            // if the custom claimer is set, then transfer the tokens to the set claimer
            XPUFETH.safeTransfer(recipient, amountToTransfer);

            emit Claimed({
                recipient: recipient,
                account: claimOrders[i].account,
                startEpoch: claimOrders[i].startEpoch,
                endEpoch: claimOrders[i].endEpoch,
                amount: amountToTransfer
            });
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
     */
    function freezeAndRevertInterval(address bridge, uint256 startEpoch, uint256 endEpoch) external restricted {
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
     */
    function revertInterval(address bridge, uint256 startEpoch, uint256 endEpoch) external restricted {
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
    function isClaimingLocked(uint256 startEpoch, uint256 endEpoch) external view returns (bool) {
        return _isClaimingLocked(getIntervalId(startEpoch, endEpoch));
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function isClaimed(uint256 startEpoch, uint256 endEpoch, address account) public view returns (bool) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimedRewards[getIntervalId(startEpoch, endEpoch)][account];
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getEpochRecord(uint256 startEpoch, uint256 endEpoch) external view returns (EpochRecord memory) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.epochRecords[getIntervalId(startEpoch, endEpoch)];
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getRewardsClaimer(address account) public view returns (address) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.rewardsClaimers[account] != address(0) ? $.rewardsClaimers[account] : account;
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getClaimingDelay() external view returns (uint256) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimingDelay;
    }

    function _handleMintAndBridge(uint256 amount, bytes memory data) internal {
        IPufferVaultV3.MintAndBridgeData memory params = abi.decode(data, (IPufferVaultV3.MintAndBridgeData));

        // Sanity check
        if (amount != (params.rewardsAmount * params.ethToPufETHRate / 1 ether)) {
            revert InvalidAmount();
        }

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        $.epochRecords[getIntervalId(params.startEpoch, params.endEpoch)] = EpochRecord({
            ethToPufETHRate: uint64(params.ethToPufETHRate),
            startEpoch: uint72(params.startEpoch),
            endEpoch: uint72(params.endEpoch),
            timeBridged: uint48(block.timestamp),
            rewardRoot: params.rewardsRoot,
            pufETHAmount: uint128(params.xPufETHAmount),
            ethAmount: uint128(params.rewardsAmount)
        });

        emit RewardRootAndRatePosted({
            rewardsAmount: params.rewardsAmount,
            ethToPufETHRate: params.ethToPufETHRate,
            startEpoch: params.startEpoch,
            endEpoch: params.endEpoch,
            rewardsRoot: params.rewardsRoot
        });
    }

    /**
     * @dev We want to allow Smart Contracts(Node Operators) on Ethereum Mainnet to set the claimer of the rewards on L2. It is likely that they will not have the same address on L2.
     */
    function _handleSetClaimer(bytes memory data) internal {
        IPufferVaultV3.SetClaimerParams memory claimerParams = abi.decode(data, (IPufferVaultV3.SetClaimerParams));

        RewardManagerStorage storage $ = _getRewardManagerStorage();
        $.rewardsClaimers[claimerParams.account] = claimerParams.claimer;

        emit ClaimerSet({ account: claimerParams.account, claimer: claimerParams.claimer });
    }

    function _setClaimingDelay(uint256 newDelay) internal {
        if (newDelay < 6 hours) {
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

        XPUFETH.approve(bridge, epochRecord.pufETHAmount);

        IBridgeInterface(bridge).xcall({
            destination: bridgeData.destinationDomainId, // Domain ID of the destination chain
            to: L1_BURNER, // Address of the target contract
            asset: address(XPUFETH), // Address of the token contract
            delegate: msg.sender, // Address that can revert or forceLocal on destination
            amount: epochRecord.pufETHAmount, // Amount of tokens to transfer
            slippage: 0, // Max slippage the user will accept in BPS (e.g. 300 = 3%)
            callData: abi.encode(epochRecord) // Encoded data to send
         });

        delete $.epochRecords[intervalId].ethToPufETHRate;
        delete $.epochRecords[intervalId].rewardRoot;
        delete $.epochRecords[intervalId].pufETHAmount;
        delete $.epochRecords[intervalId].ethAmount;

        emit ClaimingIntervalReverted({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
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
