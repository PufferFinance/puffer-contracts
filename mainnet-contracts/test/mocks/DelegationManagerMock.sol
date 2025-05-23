// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IDelegationManager } from "src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IStrategy } from "src/interface/Eigenlayer-Slashing/IStrategy.sol";
import { ISignatureUtils } from "src/interface/Eigenlayer-Slashing/ISignatureUtils.sol";
import { IStrategyManager } from "src/interface/Eigenlayer-Slashing/IStrategyManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DelegationManagerMock {
    mapping(address => bool) public isOperator;
    mapping(address => mapping(IStrategy => uint256)) public operatorShares;

    function setIsOperator(address operator, bool _isOperatorReturnValue) external {
        isOperator[operator] = _isOperatorReturnValue;
    }

    /// @notice returns the total number of shares in `strategy` that are delegated to `operator`.
    function setOperatorShares(address operator, IStrategy strategy, uint256 shares) external {
        operatorShares[operator][strategy] = shares;
    }

    mapping(address => address) public delegatedTo;

    function registerAsOperator(address initDelegationApprover, uint32 allocationDelay, string calldata metadataURI)
        external
    { }

    function delegateTo(
        address operator,
        IDelegationManager.SignatureWithExpiry memory, /*approverSignatureAndExpiry*/
        bytes32 /*approverSalt*/
    ) external {
        delegatedTo[msg.sender] = operator;
    }

    function delegateToBySignature(
        address, /*staker*/
        address, /*operator*/
        IDelegationManager.SignatureWithExpiry memory, /*stakerSignatureAndExpiry*/
        IDelegationManager.SignatureWithExpiry memory, /*approverSignatureAndExpiry*/
        bytes32 /*approverSalt*/
    ) external pure { }

    function undelegate(address staker) external returns (bytes32[] memory withdrawalRoot) {
        delegatedTo[staker] = address(0);
        return withdrawalRoot;
    }

    function increaseDelegatedShares(address, /*staker*/ IStrategy, /*strategy*/ uint256 /*shares*/ ) external pure { }

    function decreaseDelegatedShares(address, /*staker*/ IStrategy, /*strategy*/ uint256 /*shares*/ ) external pure { }

    function earningsReceiver(address operator) external pure returns (address) {
        return operator;
    }

    function delegationApprover(address operator) external pure returns (address) {
        return operator;
    }

    function stakerOptOutWindowBlocks(address /*operator*/ ) external pure returns (uint256) {
        return 0;
    }

    function minWithdrawalDelayBlocks() external pure returns (uint256) {
        return 0;
    }

    /**
     * @notice Minimum delay enforced by this contract per Strategy for completing queued withdrawals. Measured in blocks, and adjustable by this contract's owner,
     * up to a maximum of `MAX_WITHDRAWAL_DELAY_BLOCKS`. Minimum value is 0 (i.e. no delay enforced).
     */
    function strategyWithdrawalDelayBlocks(IStrategy /*strategy*/ ) external pure returns (uint256) {
        return 0;
    }

    function getOperatorShares(address operator, IStrategy[] memory strategies)
        external
        view
        returns (uint256[] memory)
    { }

    function getWithdrawalDelay(IStrategy[] calldata /*strategies*/ ) public pure returns (uint256) {
        return 0;
    }

    function isDelegated(address staker) external view returns (bool) {
        return (delegatedTo[staker] != address(0));
    }

    function isNotDelegated(address /*staker*/ ) external pure returns (bool) { }

    // function isOperator(address /*operator*/) external pure returns (bool) {}

    function stakerNonce(address /*staker*/ ) external pure returns (uint256) { }

    function delegationApproverSaltIsSpent(address, /*delegationApprover*/ bytes32 /*salt*/ )
        external
        pure
        returns (bool)
    { }

    function calculateCurrentStakerDelegationDigestHash(address, /*staker*/ address, /*operator*/ uint256 /*expiry*/ )
        external
        view
        returns (bytes32)
    { }

    function calculateStakerDelegationDigestHash(
        address, /*staker*/
        uint256, /*stakerNonce*/
        address, /*operator*/
        uint256 /*expiry*/
    ) external view returns (bytes32) { }

    function calculateDelegationApprovalDigestHash(
        address, /*staker*/
        address, /*operator*/
        address, /*_delegationApprover*/
        bytes32, /*approverSalt*/
        uint256 /*expiry*/
    ) external view returns (bytes32) { }

    function calculateStakerDigestHash(address, /*staker*/ address, /*operator*/ uint256 /*expiry*/ )
        external
        pure
        returns (bytes32 stakerDigestHash)
    { }

    function calculateApproverDigestHash(address, /*staker*/ address, /*operator*/ uint256 /*expiry*/ )
        external
        pure
        returns (bytes32 approverDigestHash)
    { }

    function calculateOperatorAVSRegistrationDigestHash(
        address, /*operator*/
        address, /*avs*/
        bytes32, /*salt*/
        uint256 /*expiry*/
    ) external pure returns (bytes32 digestHash) { }

    function DOMAIN_TYPEHASH() external view returns (bytes32) { }

    function STAKER_DELEGATION_TYPEHASH() external view returns (bytes32) { }

    function DELEGATION_APPROVAL_TYPEHASH() external view returns (bytes32) { }

    function OPERATOR_AVS_REGISTRATION_TYPEHASH() external view returns (bytes32) { }

    function domainSeparator() external view returns (bytes32) { }

    function cumulativeWithdrawalsQueued(address staker) external view returns (uint256) { }

    function calculateWithdrawalRoot(IDelegationManager.Withdrawal memory withdrawal) external pure returns (bytes32) { }

    function operatorSaltIsSpent(address avs, bytes32 salt) external view returns (bool) { }

    function queueWithdrawals(IDelegationManager.QueuedWithdrawalParams[] calldata queuedWithdrawalParams)
        external
        pure
        returns (bytes32[] memory)
    {
        bytes32[] memory roots = new bytes32[](queuedWithdrawalParams.length);
        roots[0] = bytes32("123");
        return roots;
    }

    // onlyDelegationManager functions in StrategyManager
    function addShares(
        IStrategyManager strategyManager,
        address staker,
        IERC20 token,
        IStrategy strategy,
        uint256 shares
    ) external { }

    function removeShares(IStrategyManager strategyManager, address staker, IStrategy strategy, uint256 shares)
        external
    { }

    function withdrawSharesAsTokens(
        IStrategyManager strategyManager,
        address recipient,
        IStrategy strategy,
        uint256 shares,
        IERC20 token
    ) external { }

    function operatorDetails(address operator) external view returns (IDelegationManager.OperatorDetails memory) { }

    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external { }

    function modifyOperatorDetails(address operator, address newDelegationApprover) external pure { }
    function updateOperatorMetadataURI(address operator, string calldata newMetadataURI) external pure { }
}
