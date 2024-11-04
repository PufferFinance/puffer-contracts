// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct AssetValue {
    IERC20 asset;
    uint256 value;
}

/// @title IAeraVault
/// @notice Interface for the vault.
/// @dev Any implementation MUST also implement Ownable2Step.
/// Copied and modified https://github.com/aera-finance/aera-contracts-public/blob/main/v2/interfaces/IVault.sol
interface IAeraVault {
    /// ERRORS ///

    error Aera__AssetRegistryIsZeroAddress();
    error Aera__AssetRegistryIsNotValid(address assetRegistry);
    error Aera__AssetRegistryHasInvalidVault();
    error Aera__HooksIsZeroAddress();
    error Aera__HooksIsNotValid(address hooks);
    error Aera__HooksHasInvalidVault();
    error Aera__GuardianIsZeroAddress();
    error Aera__GuardianIsOwner();
    error Aera__InitialOwnerIsZeroAddress();
    error Aera__FeeRecipientIsZeroAddress();
    error Aera__ExecuteTargetIsHooksAddress();
    error Aera__ExecuteTargetIsVaultAddress();
    error Aera__SubmitTransfersAssetFromOwner();
    error Aera__SubmitRedeemERC4626AssetFromOwner();
    error Aera__SubmitTargetIsVaultAddress();
    error Aera__SubmitTargetIsHooksAddress(uint256 index);
    error Aera__FeeRecipientIsOwner();
    error Aera__FeeIsAboveMax(uint256 actual, uint256 max);
    error Aera__CallerIsNotOwnerAndGuardian();
    error Aera__CallerIsNotGuardian();
    error Aera__AssetIsNotRegistered(IERC20 asset);
    error Aera__AmountExceedsAvailable(IERC20 asset, uint256 amount, uint256 available);
    error Aera__ExecutionFailed(bytes result);
    error Aera__VaultIsFinalized();
    error Aera__SubmissionFailed(uint256 index, bytes result);
    error Aera__CannotUseReservedFees();
    error Aera__SpotPricesReverted();
    error Aera__AmountsOrderIsIncorrect(uint256 index);
    error Aera__NoAvailableFeesForCaller(address caller);
    error Aera__NoClaimableFeesForCaller(address caller);
    error Aera__NotWrappedNativeTokenContract();
    error Aera__CannotRenounceOwnership();

    /// FUNCTIONS ///

    /// @notice Deposit assets.
    /// @param amounts Assets and amounts to deposit.
    /// @dev MUST revert if not called by owner.
    function deposit(AssetValue[] memory amounts) external;

    /// @notice Withdraw assets.
    /// @param amounts Assets and amounts to withdraw.
    /// @dev MUST revert if not called by owner.
    function withdraw(AssetValue[] memory amounts) external;

    /// @notice Set current guardian and fee recipient.
    /// @param guardian New guardian address.
    /// @param feeRecipient New fee recipient address.
    /// @dev MUST revert if not called by owner.
    function setGuardianAndFeeRecipient(address guardian, address feeRecipient) external;

    /// @notice Sets the current hooks module.
    /// @param hooks New hooks module address.
    /// @dev MUST revert if not called by owner.
    function setHooks(address hooks) external;

    /// @notice Execute a transaction via the vault.
    /// @dev Execution still should work when vault is finalized.
    /// @param operation Struct details for target and calldata to execute.
    /// @dev MUST revert if not called by owner.
    // function execute(Operation memory operation) external;

    /// @notice Terminate the vault and return all funds to owner.
    /// @dev MUST revert if not called by owner.
    function finalize() external;

    /// @notice Stops the guardian from submission and halts fee accrual.
    /// @dev MUST revert if not called by owner or guardian.
    function pause() external;

    /// @notice Resume fee accrual and guardian submissions.
    /// @dev MUST revert if not called by owner.
    function resume() external;

    /// @notice Submit a series of transactions for execution via the vault.
    /// @param operations Sequence of operations to execute.
    /// @dev MUST revert if not called by guardian.
    // function submit(Operation[] memory operations) external;

    /// @notice Claim fees on behalf of a current or previous fee recipient.
    function claim() external;

    /// @notice Get the current guardian.
    /// @return guardian Address of guardian.
    function guardian() external view returns (address guardian);

    /// @notice Get the current fee recipient.
    /// @return feeRecipient Address of fee recipient.
    function feeRecipient() external view returns (address feeRecipient);

    /// @notice Get the current asset registry.
    /// @return assetRegistry Address of asset registry.
    // function assetRegistry()
    //     external
    //     view
    //     returns (IAssetRegistry assetRegistry);

    /// @notice Get the current hooks module address.
    /// @return hooks Address of hooks module.
    // function hooks() external view returns (IHooks hooks);

    /// @notice Get fee per second.
    /// @return fee Fee per second in 18 decimal fixed point format.
    function fee() external view returns (uint256 fee);

    /// @notice Get current balances of all assets.
    /// @return assetAmounts Amounts of registered assets.
    function holdings() external view returns (AssetValue[] memory assetAmounts);

    /// @notice Get current total value of assets in vault.
    /// @return value Current total value.
    function value() external view returns (uint256 value);
}
