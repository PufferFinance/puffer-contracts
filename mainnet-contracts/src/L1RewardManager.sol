// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IL1RewardManager } from "./interface/IL1RewardManager.sol";
import { L1RewardManagerStorage } from "./L1RewardManagerStorage.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";

/**
 * @title L1RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 * @notice Mints the pufETH rewards of the node operators and lets them claim the rewards on Ethereum Mainnet.
 */
contract L1RewardManager is IL1RewardManager, L1RewardManagerStorage, AccessManagedUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;

    /**
     * @notice The minimum claiming delay
     */
    uint256 internal constant _MIN_CLAIMING_DELAY = 6 hours;

    /**
     * @notice The maximum claiming delay
     */
    uint256 internal constant _MAX_CLAIMING_DELAY = 72 hours;

    /**
     * @notice The minimum time between two mints
     */
    uint256 internal constant _MIN_MINT_FREQUENCY = 72 hours;

    /**
     * @notice The PufferVault contract on Ethereum Mainnet
     */
    PufferVaultV5 public immutable PUFFER_VAULT;

    constructor(address pufETH) {
        if (pufETH == address(0)) {
            revert InvalidAddress();
        }
        PUFFER_VAULT = PufferVaultV5(payable(pufETH));
        _disableInitializers();
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
    }

    /**
     * @notice Initializes the upgrade from the bridging version to the L1 claiming version
     * @dev Must be called in the same transaction as the upgrade (`upgradeToAndCall`).
     * Restricted to the AccessManager admin (Timelock)
     * @param claimingDelay The claiming delay for new intervals
     * @param allowedRewardMintFrequency The minimum time between two mints
     * @param deprecatedPufETHOFTAdapter The LayerZero pufETH adapter that was used for the bridging.
     * The leftover pufETH allowance of this contract to it is set to 0. Use address(0) to skip this step.
     */
    function initializeV2(uint256 claimingDelay, uint104 allowedRewardMintFrequency, address deprecatedPufETHOFTAdapter)
        external
        reinitializer(2)
        restricted
    {
        _setClaimingDelay(claimingDelay);
        _setAllowedRewardMintFrequency(allowedRewardMintFrequency);

        if (deprecatedPufETHOFTAdapter != address(0)) {
            IERC20(address(PUFFER_VAULT)).forceApprove(deprecatedPufETHOFTAdapter, 0);
        }
    }

    /**
     * @inheritdoc IL1RewardManager
     * @dev The mint amount must be lower than or equal to the allowed mint amount.
     * The minting can be done at most once per allowed frequency.
     * The newest interval must be out of its claiming delay and not frozen.
     */
    function mintRewards(MintRewardsParams calldata params) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        if (params.rewardsRoot == bytes32(0)) {
            revert InvalidRewardsRoot();
        }

        if (params.rewardsAmount == 0 || params.rewardsAmount > $.allowedRewardMintAmount) {
            revert InvalidMintAmount();
        }

        if (params.endEpoch < params.startEpoch) {
            revert InvalidEndEpoch();
        }

        if (($.lastRewardMintTimestamp + $.allowedRewardMintFrequency) > block.timestamp) {
            revert NotAllowedMintFrequency();
        }

        uint256 claimingDelay = $.claimingDelay;
        // It is 0 only if the upgrade was done without `initializeV2`. Without a delay there is no time to freeze.
        if (claimingDelay == 0) {
            revert InvalidClaimingDelay();
        }

        // A new interval can only be minted after the claiming delay of the newest interval has passed.
        // Because of this, only the newest interval can ever be frozen and reverted, so a revert
        // can always move the epoch pointer back by exactly one interval.
        {
            bytes32 newestIntervalId = $.newestIntervalId;
            Interval storage newestInterval = $.intervals[newestIntervalId];
            if (_isFreezable(newestInterval) || newestInterval.status == IntervalStatus.FROZEN) {
                revert PreviousIntervalLocked(newestIntervalId);
            }
        }

        // Update lastIntervalEndEpoch to the previous currentIntervalEndEpoch
        $.lastIntervalEndEpoch = $.currentIntervalEndEpoch;

        // Check that startEpoch is greater than the last processed end epoch
        if (params.startEpoch <= $.lastIntervalEndEpoch) {
            revert InvalidStartEpoch();
        }

        // Update current interval end epoch
        $.currentIntervalEndEpoch = params.endEpoch;

        // Update the last mint timestamp
        $.lastRewardMintTimestamp = uint48(block.timestamp);

        bytes32 intervalId = getIntervalId(params.startEpoch, params.endEpoch);

        // The epoch checks above already make this impossible. Only a reverted interval can be minted again.
        // Nothing was claimed from a reverted interval, because it was frozen before its claiming started.
        {
            IntervalStatus status = $.intervals[intervalId].status;
            if (status == IntervalStatus.ACTIVE || status == IntervalStatus.FROZEN) {
                revert IntervalAlreadyExists(intervalId);
            }
        }

        // Mint the rewards into this contract. The pufETH stays here until it is claimed
        (uint256 ethToPufETHRate, uint256 pufETHAmount) = PUFFER_VAULT.mintRewards(params.rewardsAmount);

        _storeInterval({
            intervalId: intervalId,
            params: params,
            ethToPufETHRate: ethToPufETHRate,
            pufETHAmount: pufETHAmount,
            claimableAt: block.timestamp + claimingDelay
        });

        _emitRewardsMinted(intervalId, params.rewardsURI);
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function claimRewards(ClaimOrder[] calldata claimOrders) external restricted {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        for (uint256 i = 0; i < claimOrders.length; ++i) {
            ClaimOrder calldata claimOrder = claimOrders[i];
            Interval storage interval = $.intervals[claimOrder.intervalId];

            if (interval.status == IntervalStatus.FROZEN) {
                revert IntervalIsFrozen(claimOrder.intervalId);
            }

            if (interval.status != IntervalStatus.ACTIVE) {
                revert InvalidClaimingInterval(claimOrder.intervalId);
            }

            if (block.timestamp < interval.claimableAt) {
                revert ClaimingLocked({
                    intervalId: claimOrder.intervalId,
                    account: claimOrder.account,
                    lockedUntil: interval.claimableAt
                });
            }

            if ($.claimedRewards[claimOrder.intervalId][claimOrder.account]) {
                revert AlreadyClaimed(claimOrder.intervalId, claimOrder.account);
            }

            // Alice may run many Puffer validators in the same interval `totalETHEarned = sum(aliceValidators)`
            // The leaf is: keccak256(abi.encode(AliceAddress, isL1Contract, totalETHEarned))
            // It is hashed twice to prevent second preimage attacks. This is the same leaf as on L2.
            bytes32 leaf = keccak256(
                bytes.concat(keccak256(abi.encode(claimOrder.account, claimOrder.isL1Contract, claimOrder.amount)))
            );
            if (!MerkleProof.verifyCalldata(claimOrder.merkleProof, interval.rewardsRoot, leaf)) {
                revert InvalidProof();
            }

            // Mark it claimed and transfer the tokens
            $.claimedRewards[claimOrder.intervalId][claimOrder.account] = true;

            uint256 pufETHAmount = claimOrder.amount.mulDiv(interval.ethToPufETHRate, 1 ether, Math.Rounding.Floor);

            // An interval can never pay out more than was minted for it.
            // This limits the damage of a wrong merkle root to its own interval.
            uint256 claimedPufETHAmount = interval.claimedPufETHAmount + pufETHAmount;
            if (claimedPufETHAmount > interval.pufETHAmount) {
                revert ClaimExceedsIntervalRewards(claimOrder.intervalId);
            }
            interval.claimedPufETHAmount = claimedPufETHAmount.toUint128();

            IERC20(address(PUFFER_VAULT)).safeTransfer(claimOrder.account, pufETHAmount);

            emit RewardsClaimed({
                account: claimOrder.account,
                intervalId: claimOrder.intervalId,
                amount: claimOrder.amount,
                pufETHAmount: pufETHAmount
            });
        }
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function freezeInterval(uint256 startEpoch, uint256 endEpoch) external restricted {
        _freezeInterval(startEpoch, endEpoch);
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function revertInterval(uint256 startEpoch, uint256 endEpoch) external restricted {
        _revertInterval(startEpoch, endEpoch);
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function freezeAndRevertInterval(uint256 startEpoch, uint256 endEpoch) external restricted {
        _freezeInterval(startEpoch, endEpoch);
        _revertInterval(startEpoch, endEpoch);
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
     * @notice Sets the claiming delay
     * @dev Restricted access to `ROLE_ID_DAO`
     * The new delay only applies to intervals minted after this call. Minted intervals keep their `claimableAt`.
     * @param newDelay The new claiming delay in seconds
     */
    function setClaimingDelay(uint256 newDelay) external restricted {
        _setClaimingDelay(newDelay);
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function getIntervalId(uint256 startEpoch, uint256 endEpoch) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(startEpoch, endEpoch));
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function getInterval(bytes32 intervalId) external view returns (Interval memory) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.intervals[intervalId];
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function isClaimed(bytes32 intervalId, address account) external view returns (bool) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimedRewards[intervalId][account];
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function isClaimingLocked(bytes32 intervalId) external view returns (bool) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        Interval storage interval = $.intervals[intervalId];
        return interval.status != IntervalStatus.ACTIVE || block.timestamp < interval.claimableAt;
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function getClaimingDelay() external view returns (uint256) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimingDelay;
    }

    /**
     * @inheritdoc IL1RewardManager
     */
    function getNewestIntervalId() external view returns (bytes32) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.newestIntervalId;
    }

    /**
     * @notice Returns the last successfully processed interval end epoch
     */
    function getLastIntervalEndEpoch() external view returns (uint256) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.lastIntervalEndEpoch;
    }

    /**
     * @notice Returns the current interval end epoch being processed
     */
    function getCurrentIntervalEndEpoch() external view returns (uint256) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.currentIntervalEndEpoch;
    }

    function _storeInterval(
        bytes32 intervalId,
        MintRewardsParams calldata params,
        uint256 ethToPufETHRate,
        uint256 pufETHAmount,
        uint256 claimableAt
    ) internal {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        Interval storage interval = $.intervals[intervalId];
        interval.startEpoch = params.startEpoch.toUint104();
        interval.endEpoch = params.endEpoch.toUint104();
        interval.claimableAt = claimableAt.toUint48();
        interval.pufETHAmount = pufETHAmount.toUint128();
        interval.ethAmount = params.rewardsAmount.toUint128();
        // Always 0 here, also when a reverted interval is minted again (nothing was claimed from it)
        interval.claimedPufETHAmount = 0;
        interval.status = IntervalStatus.ACTIVE;
        interval.ethToPufETHRate = ethToPufETHRate;
        interval.rewardsRoot = params.rewardsRoot;

        $.newestIntervalId = intervalId;
    }

    function _emitRewardsMinted(bytes32 intervalId, string calldata rewardsURI) internal {
        Interval storage interval = _getRewardManagerStorage().intervals[intervalId];

        emit RewardsMinted({
            intervalId: intervalId,
            rewardsRoot: interval.rewardsRoot,
            rewardsAmount: interval.ethAmount,
            pufETHAmount: interval.pufETHAmount,
            ethToPufETHRate: interval.ethToPufETHRate,
            startEpoch: interval.startEpoch,
            endEpoch: interval.endEpoch,
            claimableAt: interval.claimableAt,
            rewardsURI: rewardsURI
        });
    }

    function _freezeInterval(uint256 startEpoch, uint256 endEpoch) internal {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        bytes32 intervalId = getIntervalId(startEpoch, endEpoch);

        // Only the newest interval can be frozen, and only before its claiming starts.
        // Because of this nothing was claimed from a frozen interval.
        if (intervalId != $.newestIntervalId || !_isFreezable($.intervals[intervalId])) {
            revert UnableToFreezeInterval();
        }

        $.intervals[intervalId].status = IntervalStatus.FROZEN;

        emit IntervalFrozen({ intervalId: intervalId, startEpoch: startEpoch, endEpoch: endEpoch });
    }

    function _revertInterval(uint256 startEpoch, uint256 endEpoch) internal {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        bytes32 intervalId = getIntervalId(startEpoch, endEpoch);
        Interval storage interval = $.intervals[intervalId];

        if (interval.status != IntervalStatus.FROZEN) {
            revert UnableToRevertInterval();
        }

        interval.status = IntervalStatus.REVERTED;

        // Only the newest interval can be frozen, and no interval can be minted while it is frozen.
        // So the reverted interval is the newest one and the epoch pointer goes back to the interval before it.
        // This allows to mint the reverted epoch range again.
        $.currentIntervalEndEpoch = $.lastIntervalEndEpoch;

        // Burns the pufETH from this contract and subtracts the ETH amount from the vault's reward mint amount
        PUFFER_VAULT.revertMintRewards({ pufETHAmount: interval.pufETHAmount, ethAmount: interval.ethAmount });

        emit RevertedRewards({
            rewardsAmount: interval.ethAmount,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: interval.rewardsRoot
        });
    }

    function _setAllowedRewardMintFrequency(uint104 newFrequency) internal {
        if (newFrequency < _MIN_MINT_FREQUENCY) {
            revert InvalidMintFrequency();
        }
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        emit AllowedRewardMintFrequencyUpdated($.allowedRewardMintFrequency, newFrequency);

        $.allowedRewardMintFrequency = newFrequency;
    }

    function _setClaimingDelay(uint256 newDelay) internal {
        if (newDelay < _MIN_CLAIMING_DELAY || newDelay > _MAX_CLAIMING_DELAY) {
            revert InvalidClaimingDelay();
        }
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        emit ClaimingDelayUpdated($.claimingDelay, newDelay);

        $.claimingDelay = newDelay;
    }

    /**
     * @dev An interval can be frozen while it is active and its claiming has not started yet
     */
    function _isFreezable(Interval storage interval) internal view returns (bool) {
        return interval.status == IntervalStatus.ACTIVE && block.timestamp < interval.claimableAt;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
