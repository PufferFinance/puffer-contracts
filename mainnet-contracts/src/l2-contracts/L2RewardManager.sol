// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IL2RewardManager} from "../interface/IL2RewardManager.sol";
import {IXReceiver} from "interfaces/core/IXReceiver.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BridgingParams, BridgingType, MintAndBridgeParams, SetClaimerParams, ClaimOrder} from "../struct/RewardManagerInfo.sol";
import {AccessManagedUpgradeable} from "@openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {RewardManagerStorage} from "../struct/RewardManagerStorage.sol";

/**
 * @title L2RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract L2RewardManager is
    IL2RewardManager,
    IXReceiver,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    // The ERC20 token being distributed
    IERC20 public immutable XTOKEN;

    // keccak256(abi.encode(uint256(keccak256("L2RewardManager.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _REWARD_MANAGER_STORAGE_LOCATION =
        0x7f1aa0bc41c09fbe61ccc14f95edc9998b7136087969b5ccb26131ec2cbbc800;

    constructor(address xToken) {
        XTOKEN = IERC20(xToken);
        _disableInitializers();
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
    }

    /// @inheritdoc IL2RewardManager
    function isClaimed(
        uint64 startEpoch,
        uint64 endEpoch,
        address account
    ) public view returns (bool) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimedRewards[startEpoch][endEpoch][account];
    }

    /// @inheritdoc IL2RewardManager
    function xReceive(
        bytes32,
        uint256 _amount,
        address _asset,
        address,
        uint32,
        bytes memory _callData
    )
        external
        override(IL2RewardManager, IXReceiver)
        restricted
        returns (bytes memory)
    {
        // Decode the _callData to get the BridgingParams
        BridgingParams memory bridgingParams = abi.decode(
            _callData,
            (BridgingParams)
        );
        BridgingType bridgeType = bridgingParams.bridgingType;

        if (bridgeType == BridgingType.MintAndBridge) {
            MintAndBridgeParams memory params = abi.decode(
                bridgingParams.data,
                (MintAndBridgeParams)
            );
            // Check for the right token
            if (_asset != address(XTOKEN)) {
                revert InvalidAsset();
            }

            if (_amount < params.rewardsAmount) revert InvalidAmount();

            RewardManagerStorage storage $ = _getRewardManagerStorage();

            $.rewardRoots[params.startEpoch][params.endEpoch] = params
                .rewardsRoot;
            $.ethToPufETHRates[params.startEpoch][params.endEpoch] = params
                .ethToPufETHRate;

            emit RewardRootAndRatePosted(
                params.rewardsAmount,
                params.ethToPufETHRate,
                params.startEpoch,
                params.endEpoch,
                params.rewardsRoot
            );
        } else if (bridgeType == BridgingType.SetClaimer) {
            // Set the claimer
            SetClaimerParams memory claimerParams = abi.decode(
                bridgingParams.data,
                (SetClaimerParams)
            );
            setClaimer(claimerParams.account, claimerParams.claimer);
        } else {
            revert InvalidBridgingType();
        }

        //TODO: do something with calldata?
        return abi.encode(true);
    }

    function setClaimer(address account, address claimer) public restricted {
        // TODO: implement
    }

    /// @inheritdoc IL2RewardManager
    function claimRewards(ClaimOrder[] calldata claimOrders) external {
        uint256 length = claimOrders.length;

        for (uint256 i = 0; i < length; i++) {
            ClaimOrder memory claimOrder = claimOrders[i];
            if (
                isClaimed(
                    claimOrder.startEpoch,
                    claimOrder.endEpoch,
                    claimOrder.account
                )
            ) {
                revert AlreadyClaimed(
                    claimOrder.startEpoch,
                    claimOrder.endEpoch,
                    claimOrder.account
                );
            }
            RewardManagerStorage storage $ = _getRewardManagerStorage();

            bytes32 rewardRoot = $.rewardRoots[claimOrder.startEpoch][
                claimOrder.endEpoch
            ];
            uint128 ethToPufETHRate = $.ethToPufETHRates[claimOrder.startEpoch][
                claimOrder.endEpoch
            ];

            // Node calculated using: keccak256(abi.encode(alice, startEpoch, endEpoch, total))
            bytes32 leaf = keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(
                            claimOrder.account,
                            claimOrder.startEpoch,
                            claimOrder.endEpoch,
                            claimOrder.amount
                        )
                    )
                )
            );
            if (!MerkleProof.verify(claimOrder.merkleProof, rewardRoot, leaf))
                revert InvalidProof();

            // Mark it claimed and transfer the tokens
            $.claimedRewards[claimOrder.startEpoch][claimOrder.endEpoch][
                    claimOrder.account
                ] = true;
            uint256 amountToTransfer = claimOrder.amount * ethToPufETHRate;

            XTOKEN.safeTransfer(claimOrder.account, amountToTransfer);

            emit Claimed(
                claimOrder.account,
                claimOrder.startEpoch,
                claimOrder.endEpoch,
                amountToTransfer
            );
        }
    }

    function _getRewardManagerStorage()
        internal
        pure
        returns (RewardManagerStorage storage $)
    {
        // solhint-disable-next-line
        assembly {
            $.slot := _REWARD_MANAGER_STORAGE_LOCATION
        }
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    // slither-disable-next-line dead-code
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override restricted {}
}
