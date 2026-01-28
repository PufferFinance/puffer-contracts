// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ISignatureUtils } from "./Eigenlayer-Slashing/ISignatureUtils.sol";
import { IDelegationManagerTypes } from "./Eigenlayer-Slashing/IDelegationManager.sol";
import { IEigenPodTypes } from "./Eigenlayer-Slashing/IEigenPod.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IPermissionedModule
 * @author Puffer Finance
 * @notice Interface for the PermissionedModule contract that supports both restaked and non-restaked validators
 * @custom:security-contact security@puffer.fi
 */
interface IPermissionedModule {
    /**
     * @notice Emitted when the non-restaking withdrawal credentials contract is set
     */
    event NonRestakingWithdrawalCredentialsSet(address indexed withdrawalCredentials);

    /**
     * @notice Stakes a validator via EigenLayer (restaked path)
     * @param pubKey The validator's public key
     * @param signature The validator's signature
     * @param depositDataRoot The deposit data root
     */
    function callStakeRestaked(bytes calldata pubKey, bytes calldata signature, bytes32 depositDataRoot)
        external
        payable;

    /**
     * @notice Stakes a validator directly to Beacon Chain (non-restaked path)
     * @param pubKey The validator's public key
     * @param signature The validator's signature
     * @param depositDataRoot The deposit data root
     * @param amount The stake amount in wei (32-2048 ETH for Pectra support)
     */
    function callStakeNonRestaked(
        bytes calldata pubKey,
        bytes calldata signature,
        bytes32 depositDataRoot,
        uint256 amount
    ) external payable;

    /**
     * @notice Returns the withdrawal credentials for restaked validators (EigenPod)
     * @return The withdrawal credentials bytes
     */
    function getRestakingWithdrawalCredentials() external view returns (bytes memory);

    /**
     * @notice Returns the withdrawal credentials for non-restaked validators
     * @return The withdrawal credentials bytes
     */
    function getNonRestakingWithdrawalCredentials() external view returns (bytes memory);

    /**
     * @notice Returns the EigenPod address owned by the module
     * @return The EigenPod address
     */
    function getEigenPod() external view returns (address);

    /**
     * @notice Returns the non-restaking withdrawal credentials contract address
     * @return The NonRestakingWithdrawalCredentials contract address
     */
    function getNonRestakingWithdrawalCredentialsContract() external view returns (address);

    /**
     * @notice Returns the module name
     * @return The module name as bytes32
     */
    function NAME() external view returns (bytes32);

    /**
     * @notice Queues the withdrawal from EigenLayer for the Beacon Chain strategy
     * @param shareAmount The amount of shares to withdraw
     * @return The withdrawal roots
     */
    function queueWithdrawals(uint256 shareAmount) external returns (bytes32[] memory);

    /**
     * @notice Completes the queued withdrawals from EigenLayer
     * @param withdrawals The withdrawals to complete
     * @param tokens The tokens to receive
     * @param receiveAsTokens Whether to receive as tokens
     */
    function completeQueuedWithdrawals(
        IDelegationManagerTypes.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external;

    /**
     * @notice Delegates to an EigenLayer operator
     * @param operator The operator address
     * @param approverSignatureAndExpiry The approver signature and expiry
     * @param approverSalt The approver salt
     */
    function callDelegateTo(
        address operator,
        ISignatureUtils.SignatureWithExpiry calldata approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external;

    /**
     * @notice Undelegates from the current EigenLayer operator
     * @return The withdrawal roots
     */
    function callUndelegate() external returns (bytes32[] memory);

    /**
     * @notice Triggers the validators exit for the given pubkeys (restaked validators via EigenPod)
     * @param pubkeys The pubkeys of the validators to exit
     */
    function triggerRestakedValidatorsExit(bytes[] calldata pubkeys) external payable;

    /**
     * @notice Triggers withdrawal requests for non-restaked validators via EIP-7002
     * @param requests The withdrawal requests with pubkey and amountGwei
     * @dev Uses NonRestakingWithdrawalCredentials contract.
     *      - amountGwei == 0: Full validator exit
     *      - amountGwei > 0: Partial withdrawal (Pectra feature, requires 0x02 credentials)
     */
    function triggerNonRestakedValidatorWithdrawals(IEigenPodTypes.WithdrawalRequest[] calldata requests)
        external
        payable;

    /**
     * @notice Withdraws accumulated ETH from non-restaking withdrawal credentials to this module
     */
    function withdrawNonRestakedETH() external;

    /**
     * @notice Sets the proof submitter on the EigenPod
     * @param proofSubmitter The address of the proof submitter
     */
    function setProofSubmitter(address proofSubmitter) external;

    /**
     * @notice Sets the rewards claimer for EigenLayer rewards
     * @param claimer The address of the claimer
     */
    function callSetClaimerFor(address claimer) external;

    /**
     * @notice Executes a custom call from the module
     * @param to The target address
     * @param amount The ETH amount to send
     * @param data The call data
     * @return success Whether the call succeeded
     * @return returnData The return data from the call
     */
    function call(address to, uint256 amount, bytes calldata data) external returns (bool success, bytes memory);
}
