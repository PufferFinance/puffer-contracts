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
import { ClaimOrder, EpochRecord } from "./struct/L2RewardManagerInfo.sol";

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

    IERC20 public immutable XPUFETH;

    address public immutable L1_PUFFER_VAULT;

    constructor(address xPufETH, address l1PufferVault) {
        XPUFETH = IERC20(xPufETH);
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
    function isClaimed(uint256 startEpoch, uint256 endEpoch, address account) public view returns (bool) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimedRewards[startEpoch][endEpoch][account];
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    function getEpochRecord(uint256 startEpoch, uint256 endEpoch) external view returns (EpochRecord memory) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.epochRecords[startEpoch][endEpoch];
    }

    /**
     * @inheritdoc IL2RewardManager
     */
    // TODO restricted = Assign bridge role to allowed bridges.
    function xReceive(bytes32, uint256 amount, address, address originSender, uint32, bytes memory callData)
        external
        override(IL2RewardManager, IXReceiver)
        onlyPufferVault(originSender)
        restricted
        returns (bytes memory)
    {
        IPufferVaultV3.BridgingParams memory bridgingParams = abi.decode(callData, (IPufferVaultV3.BridgingParams));

        if (bridgingParams.bridgingType == IPufferVaultV3.BridgingType.MintAndBridge) {
            _handleMintAndBridge(amount, bridgingParams.data);
        } else if (bridgingParams.bridgingType == IPufferVaultV3.BridgingType.SetClaimer) {
            _handleSetClaimer(bridgingParams.data);
        } else {
            revert InvalidBridgingType();
        }
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

            EpochRecord storage epochRecord = $.epochRecords[claimOrder.startEpoch][claimOrder.endEpoch];

            // Node calculated using: keccak256(abi.encode(alice, startEpoch, endEpoch, total))
            bytes32 leaf = keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(claimOrder.account, claimOrder.startEpoch, claimOrder.endEpoch, claimOrder.amount)
                    )
                )
            );
            if (!MerkleProof.verify(claimOrder.merkleProof, epochRecord.rewardRoot, leaf)) {
                revert InvalidProof();
            }

            // Mark it claimed and transfer the tokens
            $.claimedRewards[claimOrder.startEpoch][claimOrder.endEpoch][claimOrder.account] = true;

            uint256 amountToTransfer = claimOrder.amount * epochRecord.ethToPufETHRate / 1 ether;

            address recipient = $.rewardsClaimers[claimOrder.account] == address(0)
                ? claimOrder.account
                : $.rewardsClaimers[claimOrder.account];

            // if the custom claimer is set, then transfer the tokens to the set claimer
            XPUFETH.safeTransfer(recipient, amountToTransfer);

            emit Claimed({
                account: claimOrder.account,
                recipient: recipient,
                startEpoch: claimOrder.startEpoch,
                endEpoch: claimOrder.endEpoch,
                amount: amountToTransfer
            });
        }
    }

    function _handleMintAndBridge(uint256 amount, bytes memory data) internal {
        IPufferVaultV3.MintAndBridgeData memory params = abi.decode(data, (IPufferVaultV3.MintAndBridgeData));

        // Validate that the exchange rate is correct //@todo might be problematic, but it shouldnt
        if (amount != (params.rewardsAmount * params.ethToPufETHRate / 1 ether)) {
            revert InvalidAmount();
        }

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        // Store the rate and root
        $.epochRecords[params.startEpoch][params.endEpoch] =
            EpochRecord({ ethToPufETHRate: params.ethToPufETHRate, rewardRoot: params.rewardsRoot });

        emit RewardRootAndRatePosted({
            rewardsAmount: params.rewardsAmount,
            ethToPufETHRate: params.ethToPufETHRate,
            startEpoch: params.startEpoch,
            endEpoch: params.endEpoch,
            root: params.rewardsRoot
        });
    }

    function _handleSetClaimer(bytes memory data) internal {
        IPufferVaultV3.SetClaimerParams memory claimerParams = abi.decode(data, (IPufferVaultV3.SetClaimerParams));

        RewardManagerStorage storage $ = _getRewardManagerStorage();
        $.rewardsClaimers[claimerParams.account] = claimerParams.claimer;

        emit ClaimerSet({ account: claimerParams.account, claimer: claimerParams.claimer });
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    // slither-disable-next-line dead-code
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
