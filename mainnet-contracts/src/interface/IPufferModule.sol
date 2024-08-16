// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";
import { BeaconChainProofs } from "eigenlayer/libraries/BeaconChainProofs.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IPufferModule
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufferModule {
    /**
     * @notice Thrown if the rewards are already claimed for a `blockNumber`
     * @dev Signature "0xa9214540"
     */
    error AlreadyClaimed(uint256 blockNumber, address node);

    /**
     * @notice Thrown if guardians try to post root for an invalid block number
     * @dev Signature "0x9f4aafbe"
     */
    error InvalidBlockNumber(uint256 blockNumber);

    /**
     * @notice Thrown if the there is nothing to be claimed for the provided information
     * @dev Signature "0x64ab3466"
     */
    error NothingToClaim(address node);

    /**
     * @notice Emitted when the rewards MerkleRoot `root` for a `blockNumber` is posted
     */
    event RewardsRootPosted(uint256 indexed blockNumber, bytes32 root);

    /**
     * @notice Emits when rewards are claimed
     * @param node is the node address
     * @param amount is the amount claimed in wei
     */
    event RewardsClaimed(address indexed node, uint256 amount);

    /**
     * @notice Returns the Withdrawal credentials for that module
     */
    function getWithdrawalCredentials() external view returns (bytes memory);

    /**
     * @notice Returns the module name
     */
    function NAME() external view returns (bytes32);

    /**
     * @notice Starts the validator
     */
    function callStake(bytes calldata pubKey, bytes calldata signature, bytes32 depositDataRoot) external payable;

    /**
     * @notice Sets the proof submitter on the EigenPod
     */
    function setProofSubmitter(address proofSubmitter) external;

    /**
     * @notice Calls the delegateTo function on the EigenLayer delegation manager
     * @param operator is the address of the restaking operator
     * @param approverSignatureAndExpiry the signature of the delegation approver
     * @param approverSalt salt for the signature
     * @dev Restricted to the DAO
     */
    function callDelegateTo(
        address operator,
        ISignatureUtils.SignatureWithExpiry calldata approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external;

    /**
     * @notice Calls the undelegate function on the EigenLayer delegation manager
     * @dev Restricted to the DAO
     */
    function callUndelegate() external returns (bytes32[] memory withdrawalRoot);

    /**
     * @notice Returns the EigenPod address owned by the module
     */
    function getEigenPod() external view returns (address);

    /**
     * @notice Queues the withdrawal from EigenLayer for the Beacon Chain strategy
     * @dev Restricted to PufferModuleManager
     */
    function queueWithdrawals(uint256 shareAmount) external returns (bytes32[] memory);

    /**
     * @notice Completes the queued withdrawals
     */
    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) external;

    /**
     * @notice Starts the checkpoint for the module
     */
    function startCheckpoint() external;

    /**
     * @notice Function callable only by PufferProtocol
     * @param to is the destination address
     * @param amount is the ETH amount in wei
     * @param data is the calldata
     */
    function call(address to, uint256 amount, bytes calldata data)
        external
        returns (bool success, bytes memory response);

    /**
     * @notice Sets the rewards claimer to `claimer` for the PufferModule
     */
    function callSetClaimerFor(address claimer) external;
}
