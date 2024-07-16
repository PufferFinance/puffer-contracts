// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IL2RewardManager} from "../interface/IL2RewardManager.sol";
import {IXReceiver} from "interfaces/core/IXReceiver.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BridgingParams} from "../struct/BridgingParams.sol";
import {AccessManagedUpgradeable} from "@openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

/**
 * @title L2RewardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract L2RewardManager is
    IL2RewardManager,
    IXReceiver,
    AccessManagedUpgradeable
{
    using SafeERC20 for IERC20;
    // The ERC20 token being distributed
    IERC20 public immutable XTOKEN;

    // Mapping of startEpoch and endEpoch to Merkle root
    mapping(uint64 startEpoch => mapping(uint64 endEpoch => bytes32 rewardRoot))
        public rewardRoots;

    /**
     * @notice Mapping to track claimed tokens for users for each unique epoch range
     * @dev claimed[1][5][Alice's address] = true;  // If Alice claimed Reward 1
     * claimed[6][10][Alice's address] = true; // If Alice claimed Reward 2
     */
    mapping(uint64 startEpoch => mapping(uint64 endEpoch => mapping(address account => bool isClaimed)))
        private claimed;

    constructor(address xToken) {
        XTOKEN = IERC20(xToken);
    }

    /// @inheritdoc IL2RewardManager
    function isClaimed(
        uint64 startEpoch,
        uint64 endEpoch,
        address account
    ) public view returns (bool) {
        return claimed[startEpoch][endEpoch][account];
    }

    /// @inheritdoc IL2RewardManager
    function xReceive(
        bytes32,
        uint256 _amount,
        address _asset,
        address,
        uint32,
        bytes memory _callData
    ) external override(IL2RewardManager, IXReceiver) returns (bytes memory) {
        // Check for the right token
        if (_asset != address(XTOKEN)) {
            revert InvalidAsset();
        }

        // Decode the _callData to get the BridgingParams
        BridgingParams memory params = abi.decode(_callData, (BridgingParams));

        if (_amount < params.rewardsAmount) {
            revert InvalidAmount();
        }

        emit RewardAmountReceived(
            params.startEpoch,
            params.endEpoch,
            params.rewardsRoot,
            params.rewardsAmount
        );
        //TODO: do something with calldata?
        return abi.encode(true);
    }

    /// @inheritdoc IL2RewardManager
    function postRewardsRoot(
        uint64 startEpoch,
        uint64 endEpoch,
        bytes32 root
    ) external restricted {
        rewardRoots[startEpoch][endEpoch] = root;
        emit RewardsRootPosted(startEpoch, endEpoch, root);
    }

    /// @inheritdoc IL2RewardManager
    function claimRewards(
        uint64[] calldata startEpochs,
        uint64[] calldata endEpochs,
        address[] calldata accounts,
        uint256[] calldata amounts,
        bytes32[][] calldata merkleProofs
    ) external {
        if (
            startEpochs.length != endEpochs.length ||
            startEpochs.length != accounts.length ||
            startEpochs.length != amounts.length ||
            startEpochs.length != merkleProofs.length
        ) revert InvalidInputLength();

        for (uint256 i = 0; i < startEpochs.length; i++) {
            if (isClaimed(startEpochs[i], endEpochs[i], accounts[i])) {
                revert AlreadyClaimed(
                    startEpochs[i],
                    endEpochs[i],
                    accounts[i]
                );
            }

            bytes32 rewardRoot = rewardRoots[startEpochs[i]][endEpochs[i]];

            // Node calculated using: keccak256(abi.encode(alice, startEpoch, endEpoch, total))
            bytes32 leaf = keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(
                            accounts[i],
                            startEpochs[i],
                            endEpochs[i],
                            amounts[i]
                        )
                    )
                )
            );
            if (!MerkleProof.verifyCalldata(merkleProofs[i], rewardRoot, leaf))
                revert InvalidProof();

            // Mark it claimed and transfer the tokens
            claimed[startEpochs[i]][endEpochs[i]][accounts[i]] = true;

            XTOKEN.safeTransfer(accounts[i], amounts[i]);

            emit Claimed(accounts[i], startEpochs[i], endEpochs[i], amounts[i]);
        }
    }
}
