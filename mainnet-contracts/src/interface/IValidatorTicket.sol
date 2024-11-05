// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferOracle } from "../interface/IPufferOracle.sol";
import { Permit } from "../structs/Permit.sol";

/**
 * @title IValidatorTicket
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IValidatorTicket {
    /**
     * @dev Thrown when the user tries to purchase VT with an invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Thrown if the oracle tries to submit invalid data
     * @dev Signature "0x5cb045db"
     */
    error InvalidData();

    /**
     * @dev Thrown when the recipient address is zero
     */
    error RecipientIsZeroAddress();

    /**
     * @notice Emitted when the ETH `amount` in wei is transferred to `to` address
     * @dev Signature "0xba7bb5aa419c34d8776b86cc0e9d41e72d74a893a511f361a11af6c05e920c3d"
     */
    event TransferredETH(address indexed to, uint256 amount);

    /**
     * @notice Emitted when the ETH is split between treasury, guardians and vault
     * @dev Signature "0x8476c087a9e2adf34e598e2ef90747a2824cf1bd88e16bdb0ef56d5d6bddff27"
     */
    event DispersedETH(uint256 treasury, uint256 guardians, uint256 vault);

    /**
     * @notice Emitted when the pufETH is split between treasury, guardians and the amount burned
     */
    event DispersedPufETH(uint256 treasury, uint256 guardians, uint256 burned);

    /**
     * @notice Emitted when the protocol fee rate is changed
     * @dev Signature "0xb51bef650ff5ad43303dbe2e500a74d4fd1bdc9ae05f046bece330e82ae0ba87"
     */
    event ProtocolFeeChanged(uint256 oldTreasuryFee, uint256 newTreasuryFee);

    /**
     * @notice Emitted when the protocol fee rate is changed
     * @dev Signature "0x0a3e0a163d4dfba5f018c5c1e2214007151b3abb0907e3ae402ae447c7e1bc47"
     */
    event GuardiansFeeChanged(uint256 oldGuardiansFee, uint256 newGuardiansFee);

    /**
     * @notice Mints VT to `recipient` corresponding to sent ETH and distributes funds between the Treasury, Guardians and PufferVault
     * @param recipient The address to mint VT to
     * @dev restricted modifier is also used as `whenNotPaused`
     * @return Amount of VT minted
     */
    function purchaseValidatorTicket(address recipient) external payable returns (uint256);

    /**
     * @notice Purchases Validator Tickets with pufETH
     * @param recipient The address to receive the minted VTs
     * @param vtAmount The amount of Validator Tickets to purchase
     * @return pufEthUsed The amount of pufETH used for the purchase
     */
    function purchaseValidatorTicketWithPufETH(address recipient, uint256 vtAmount)
        external
        returns (uint256 pufEthUsed);

    /**
     * @notice Purchases Validator Tickets with pufETH using permit
     * @param recipient The address to receive the minted VTs
     * @param vtAmount The amount of Validator Tickets to purchase
     * @param permitData The permit data for the pufETH transfer
     * @return pufEthUsed The amount of pufETH used for the purchase
     */
    function purchaseValidatorTicketWithPufETHAndPermit(address recipient, uint256 vtAmount, Permit calldata permitData)
        external
        returns (uint256 pufEthUsed);

    /**
     * @notice Retrieves the current guardians fee rate
     * @return The current guardians fee rate
     */
    function getGuardiansFeeRate() external view returns (uint256);

    /**
     * @notice Returns the Puffer Vault (pufETH)
     */
    function PUFFER_VAULT() external view returns (address payable);

    /**
     * @notice Returns the Treasury
     */
    function TREASURY() external view returns (address payable);

    /**
     * @notice Returns the GuardianModule
     */
    function GUARDIAN_MODULE() external view returns (address payable);

    /**
     * @notice Returns the Puffer Oracle
     */
    function PUFFER_ORACLE() external view returns (IPufferOracle);

    /**
     * @notice Returns the Operations Multisig
     */
    function OPERATIONS_MULTISIG() external view returns (address);

    /**
     * @notice Retrieves the current protocol fee rate
     * @return The current protocol fee rate
     */
    function getProtocolFeeRate() external view returns (uint256);
}
