// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferOracleV2 } from "./PufferOracleV2.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

/**
 * @title OperationsCoordinator
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract OperationsCoordinator is AccessManaged {
    /**
     * @notice Thrown if the new price is out of range
     */
    error InvalidPrice();

    /**
     * @notice Thrown if the new price change tolerance is out of range
     */
    error InvalidPriceChangeToleranceBPS();

    /**
     * @dev Emitted when the price change tolerance is updated
     * @param oldValue the old tolerance value
     * @param newValue the new tolerance value
     */
    event PriceChangeToleranceBPSUpdated(uint256 oldValue, uint256 newValue);

    uint256 internal constant _BPS_DECIMALS = 1e4; // 100%

    PufferOracleV2 internal immutable _ORACLE;

    uint256 internal _priceChangeToleranceBps;

    constructor(PufferOracleV2 oracle, address accessManager, uint256 priceChangeToleranceBps)
        AccessManaged(accessManager)
    {
        _ORACLE = oracle;
        _priceChangeToleranceBps = priceChangeToleranceBps;
    }

    /**
     * @notice Updates the allowed price change tolerance percentage
     * @dev Restricted to the Operations Multisig
     */
    function setPriceChangeToleranceBps(uint256 newValue) external restricted {
        if (newValue > _BPS_DECIMALS) {
            revert InvalidPriceChangeToleranceBPS();
        }

        emit PriceChangeToleranceBPSUpdated(_priceChangeToleranceBps, newValue);

        _priceChangeToleranceBps = newValue;
    }

    /**
     * @notice Updates the VT mint price on the PufferOracle
     * @dev Restricted to the Puffer Paymaster
     */
    function setValidatorTicketMintPrice(uint256 newPrice) external restricted {
        if (newPrice == 0) {
            revert InvalidPrice();
        }

        if (!isWithinRange(newPrice)) {
            revert InvalidPrice();
        }

        _ORACLE.setMintPrice(newPrice);
    }

    /**
     * @notice Returns the current price change tolerance in basis points
     * @return the current price change tolerance
     */
    function getPriceChangeToleranceBps() external view returns (uint256) {
        return _priceChangeToleranceBps;
    }

    /**
     * @notice Checks if the new price is within the allowed range
     * @param newPrice The new price to set for minting VT
     * @return true if the new price is within the allowed range
     */
    function isWithinRange(uint256 newPrice) public view returns (bool) {
        uint256 oldPrice = _ORACLE.getValidatorTicketPrice();
        uint256 allowedDifference = (oldPrice * _priceChangeToleranceBps) / _BPS_DECIMALS;

        // Addition and subtraction have bigger precedence than comparison
        // https://docs.soliditylang.org/en/latest/cheatsheet.html
        if (newPrice > oldPrice) {
            return newPrice <= oldPrice + allowedDifference;
        }

        return newPrice >= oldPrice - allowedDifference;
    }
}
