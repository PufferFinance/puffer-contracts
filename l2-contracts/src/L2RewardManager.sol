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
import { ClaimOrder } from "./struct/ClaimOrder.sol";

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
    function isClaimed(uint64 startEpoch, uint64 endEpoch, address account) public view returns (bool) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();
        return $.claimedRewards[startEpoch][endEpoch][account];
    }

    /**
     * @inheritdoc IL2RewardManager
     * // todo restricted = Assign bridge role to allowed bridges.
     */
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

            RateAndRoot storage rateAndRoot = $.rateAndRoots[claimOrder.startEpoch][claimOrder.endEpoch];

            // Node calculated using: keccak256(abi.encode(alice, startEpoch, endEpoch, total))
            bytes32 leaf = keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(claimOrder.account, claimOrder.startEpoch, claimOrder.endEpoch, claimOrder.amount)
                    )
                )
            );
            if (!MerkleProof.verify(claimOrder.merkleProof, rateAndRoot.rewardRoot, leaf)) {
                revert InvalidProof();
            }

            // Mark it claimed and transfer the tokens
            $.claimedRewards[claimOrder.startEpoch][claimOrder.endEpoch][claimOrder.account] = true;

            uint256 amountToTransfer = claimOrder.amount * rateAndRoot.ethToPufETHRate / 1 ether;

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

    function _handleMintAndBridge(uint256 amount, uint256 ethToPufETH, bytes calldata data) internal {
        IPufferVaultV3.MintAndBridgeParams memory params = abi.decode(data, (IPufferVaultV3.MintAndBridgeParams));

        // Validate that the exchange rate is correct //@todo might be problematic, but it shouldnt
        if (amount != (params.rewardsAmount * params.ethToPufETHRate / 1 ether)) {
            revert InvalidAmount();
        }

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        // Store the rate and root
        $.rateAndRoots[params.startEpoch][params.endEpoch] =
            RateAndRoot({ ethToPufETHRate: params.ethToPufETHRate, rewardRoot: params.rewardsRoot });

        emit RewardRootAndRatePosted({
            rewardsAmount: params.rewardsAmount,
            ethToPufETHRate: params.ethToPufETHRate,
            startEpoch: params.startEpoch,
            endEpoch: params.endEpoch,
            root: params.rewardsRoot
        });
    }

    function _handleSetClaimer(bytes calldata data) internal {
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
