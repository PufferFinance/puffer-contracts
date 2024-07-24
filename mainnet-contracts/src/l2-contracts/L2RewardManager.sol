// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {
    BridgingParams,
    BridgingType,
    ClaimOrder,
    MintAndBridgeParams,
    SetClaimerParams
} from "../struct/L2RewardManagerInfo.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IL2RewardManager } from "../interface/IL2RewardManager.sol";
import { IXReceiver } from "@connext/interfaces/core/IXReceiver.sol";
import { L2RewardManagerStorage } from "./L2RewardManagerStorage.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

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
    using Math for uint256;
    using Math for uint128;

    // The ERC20 token being distributed
    IERC20 public immutable xPufETH;

    address public immutable L1_PUFFER_VAULT;

    constructor(address _xPufETH, address l1PufferVault) {
        xPufETH = IERC20(_xPufETH);
        L1_PUFFER_VAULT = l1PufferVault;
        _disableInitializers();
    }

    modifier onlyPufferVault(address originSender) {
        if (originSender != address(L1_PUFFER_VAULT)) {
            revert CallerNotPufferVault();
        }
        _;
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function isClaimed(uint64 startEpoch, uint64 endEpoch, address account) public view returns (bool) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimedRewards[startEpoch][endEpoch][account];
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function xReceive(bytes32, uint256 amount, address asset, address originSender, uint32, bytes memory callData)
        external
        override(IL2RewardManager, IXReceiver)
        onlyPufferVault(originSender)
        returns (bytes memory)
    {
        // Decode the callData to get the BridgingParams
        BridgingParams memory bridgingParams = abi.decode(callData, (BridgingParams));
        BridgingType bridgeType = bridgingParams.bridgingType;

        if (bridgeType == BridgingType.MintAndBridge) {
            MintAndBridgeParams memory params = abi.decode(bridgingParams.data, (MintAndBridgeParams));
            // Check for the right token
            if (asset != address(xPufETH)) {
                revert InvalidAsset();
            }

            if (amount != params.rewardsAmount.mulDiv(params.ethToPufETHRate, 1 ether, Math.Rounding.Floor)) {
                revert InvalidAmount();
            }

            RewardManagerStorage storage $ = _getRewardManagerStorage();

            // Store the rate and root
            $.rateAndRoots[params.startEpoch][params.endEpoch] =
                RateAndRoot({ ethToPufETHRate: params.ethToPufETHRate, rewardRoot: params.rewardsRoot });

            emit RewardRootAndRatePosted(
                params.rewardsAmount, params.ethToPufETHRate, params.startEpoch, params.endEpoch, params.rewardsRoot
            );
        } else if (bridgeType == BridgingType.SetClaimer) {
            // Set the claimer
            SetClaimerParams memory claimerParams = abi.decode(bridgingParams.data, (SetClaimerParams));
            RewardManagerStorage storage $ = _getRewardManagerStorage();
            $.customClaimers[claimerParams.account] = claimerParams.claimer;

            emit ClaimerSet(claimerParams.account, claimerParams.claimer);
        } else {
            revert InvalidBridgingType();
        }

        //TODO: do something with calldata?
        return abi.encode(true);
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function claimRewards(ClaimOrder[] calldata claimOrders) external {
        uint256 length = claimOrders.length;

        for (uint256 i = 0; i < length; i++) {
            ClaimOrder memory claimOrder = claimOrders[i];
            if (isClaimed(claimOrder.startEpoch, claimOrder.endEpoch, claimOrder.account)) {
                revert AlreadyClaimed(claimOrder.startEpoch, claimOrder.endEpoch, claimOrder.account);
            }
            RewardManagerStorage storage $ = _getRewardManagerStorage();

            RateAndRoot storage rateAndRoot = $.rateAndRoots[claimOrder.startEpoch][claimOrder.endEpoch];

            // Node calculated using: keccak256(abi.encode(alice, startEpoch, endEpoch, total))
            bytes32 leaf = keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(claimOrder.account, claimOrder.startEpoch, claimOrder.endEpoch, claimOrder.amount)
                    )
                )
            );
            if (!MerkleProof.verify(claimOrder.merkleProof, rateAndRoot.rewardRoot, leaf)) revert InvalidProof();

            // Mark it claimed and transfer the tokens
            $.claimedRewards[claimOrder.startEpoch][claimOrder.endEpoch][claimOrder.account] = true;
            uint256 amountToTransfer =
                claimOrder.amount.mulDiv(rateAndRoot.ethToPufETHRate, 1 ether, Math.Rounding.Floor);

            // if the custom claimer is set, then transfer the tokens to the set claimer
            xPufETH.safeTransfer(
                ($.customClaimers[claimOrder.account] == address(0))
                    ? claimOrder.account
                    : $.customClaimers[claimOrder.account],
                amountToTransfer
            );

            emit Claimed(claimOrder.account, claimOrder.startEpoch, claimOrder.endEpoch, amountToTransfer);
        }
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    // slither-disable-next-line dead-code
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
