// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ValidatorTicketStorage } from "./ValidatorTicketStorage.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IPufferOracle } from "./interface/IPufferOracle.sol";
import { IValidatorTicket } from "./interface/IValidatorTicket.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ValidatorTicket
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract ValidatorTicket is
    IValidatorTicket,
    ValidatorTicketStorage,
    UUPSUpgradeable,
    AccessManagedUpgradeable,
    ERC20PermitUpgradeable
{
    using SafeERC20 for address;
    using Address for address payable;
    using Math for uint256;

    /**
     * @inheritdoc IValidatorTicket
     */
    address payable public immutable override TREASURY;

    /**
     * @inheritdoc IValidatorTicket
     */
    address payable public immutable override GUARDIAN_MODULE;

    /**
     * @inheritdoc IValidatorTicket
     */
    address payable public immutable override PUFFER_VAULT;

    /**
     * @inheritdoc IValidatorTicket
     */
    IPufferOracle public immutable override PUFFER_ORACLE;

    /**
     * @dev Basis point scale
     */
    uint256 private constant _BASIS_POINT_SCALE = 1e4;

    /**
     * @dev Threshold for acceptable fee rate percentage
     */
    uint256 private constant _FEE_RATE_THRESHOLD_BPS = 1000;

    constructor(
        address payable guardianModule,
        address payable treasury,
        address payable pufferVault,
        IPufferOracle pufferOracle
    ) {
        if (
            guardianModule == address(0) || treasury == address(0) || pufferVault == address(0)
                || address(pufferOracle) == address(0)
        ) {
            revert InvalidData();
        }
        PUFFER_ORACLE = pufferOracle;
        GUARDIAN_MODULE = guardianModule;
        PUFFER_VAULT = pufferVault;
        TREASURY = treasury;
        _disableInitializers();
    }

    function initialize(address accessManager, uint256 treasuryFeeRate, uint256 guardiansFeeRate)
        external
        initializer
    {
        __AccessManaged_init(accessManager);
        __ERC20_init("Puffer Validator Ticket", "VT");
        __ERC20Permit_init("Puffer Validator Ticket");
        _setProtocolFeeRate(treasuryFeeRate);
        _setGuardiansFeeRate(guardiansFeeRate);
    }

    /**
     * @inheritdoc IValidatorTicket
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function purchaseValidatorTicket(address recipient)
        external
        payable
        virtual
        restricted
        returns (uint256 mintedAmount)
    {
        ValidatorTicket storage $ = _getValidatorTicketStorage();

        uint256 mintPrice = PUFFER_ORACLE.getValidatorTicketPrice();
        mintedAmount = (msg.value * 1 ether) / mintPrice; // * 1 ether is to upscale amount to 18 decimals

        // slither-disable-next-line divide-before-multiply
        _mint(recipient, mintedAmount);

        // If we are over the burst threshold, keep everything
        // That means that pufETH holders are not getting any new rewards until it goes under the threshold
        if (PUFFER_ORACLE.isOverBurstThreshold()) {
            // Everything goes to the treasury
            TREASURY.sendValue(msg.value);
            emit DispersedETH({ treasury: msg.value, guardians: 0, vault: 0 });
            return mintedAmount;
        }

        uint256 treasuryAmount = _sendETH(TREASURY, msg.value, $.protocolFeeRate);
        uint256 guardiansAmount = _sendETH(GUARDIAN_MODULE, msg.value, $.guardiansFeeRate);
        uint256 vaultAmount = msg.value - (treasuryAmount + guardiansAmount);
        // The remainder belongs to PufferVault
        PUFFER_VAULT.sendValue(vaultAmount);
        emit DispersedETH({ treasury: treasuryAmount, guardians: guardiansAmount, vault: vaultAmount });
    }

    /**
     * @notice Burns `amount` from the transaction sender
     * @dev Restricted to the PufferProtocol
     */
    function burn(uint256 amount) external virtual restricted {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Updates the treasury fee
     * @dev Restricted to the DAO
     * (10,000 = 100%, 100 = 1%) 10% is the maximum value defined in the _setProtocolFeeRate function
     * @param newProtocolFeeRate The new treasury fee rate
     */
    function setProtocolFeeRate(uint256 newProtocolFeeRate) external virtual restricted {
        _setProtocolFeeRate(newProtocolFeeRate);
    }

    /**
     * @notice Updates the guardians fee rate
     * @dev Restricted to the DAO
     * (10,000 = 100%, 100 = 1%) 10% is the maximum value defined in the _setProtocolFeeRate function
     * @param newGuardiansFeeRate The new guardians fee rate
     */
    function setGuardiansFeeRate(uint256 newGuardiansFeeRate) external virtual restricted {
        _setGuardiansFeeRate(newGuardiansFeeRate);
    }

    /**
     * @inheritdoc IValidatorTicket
     */
    function getProtocolFeeRate() external view virtual returns (uint256) {
        ValidatorTicket storage $ = _getValidatorTicketStorage();
        return $.protocolFeeRate;
    }

    /**
     * @inheritdoc IValidatorTicket
     */
    function getGuardiansFeeRate() external view virtual returns (uint256) {
        ValidatorTicket storage $ = _getValidatorTicketStorage();
        return $.guardiansFeeRate;
    }

    /**
     * @param rate represents the percentage of the amount to send
     * @dev Calculates the amount to send and sends it to the recipient
     * rate is in basis points (100 = 1)
     * This is for sending ETH to trusted addresses (no reentrancy protection)
     * PufferVault, Guardians, Treasury
     */
    function _sendETH(address to, uint256 amount, uint256 rate) internal virtual returns (uint256 toSend) {
        toSend = amount.mulDiv(rate, _BASIS_POINT_SCALE, Math.Rounding.Ceil);

        if (toSend != 0) {
            payable(to).sendValue(toSend);
        }
    }

    function _setProtocolFeeRate(uint256 newProtocolFeeRate) internal virtual {
        ValidatorTicket storage $ = _getValidatorTicketStorage();
        // Treasury fee can not be bigger than 10%
        if (newProtocolFeeRate > (_FEE_RATE_THRESHOLD_BPS)) {
            revert InvalidData();
        }
        emit ProtocolFeeChanged($.protocolFeeRate, newProtocolFeeRate);
        $.protocolFeeRate = SafeCast.toUint128(newProtocolFeeRate);
    }

    function _setGuardiansFeeRate(uint256 newGuardiansFeeRate) internal virtual {
        ValidatorTicket storage $ = _getValidatorTicketStorage();
        // Treasury fee can not be bigger than 10%
        if (newGuardiansFeeRate > (_FEE_RATE_THRESHOLD_BPS)) {
            revert InvalidData();
        }
        emit GuardiansFeeChanged($.guardiansFeeRate, newGuardiansFeeRate);
        $.guardiansFeeRate = SafeCast.toUint128(newGuardiansFeeRate);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
