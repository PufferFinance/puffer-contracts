// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferOracle } from "./interface/IPufferOracle.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

/**
 * @title PufferOracle
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PufferOracle is IPufferOracle, AccessManaged {
    /**
     * @dev Price in wei to mint one Validator Ticket
     */
    uint256 internal _validatorTicketPrice;

    constructor(address accessManager) AccessManaged(accessManager) {
        _setMintPrice(0.01 ether);
    }

    /**
     * @inheritdoc IPufferOracle
     */
    function getLockedEthAmount() external pure returns (uint256) {
        return 0;
    }

    /**
     * @inheritdoc IPufferOracle
     */
    function isOverBurstThreshold() external pure returns (bool) {
        return false;
    }

    /**
     * @inheritdoc IPufferOracle
     */
    function getValidatorTicketPrice() external view returns (uint256 pricePerVT) {
        return _validatorTicketPrice;
    }

    /**
     * @notice Updates the price to mint VT
     * @param newPrice The new price to set for minting VT
     * @dev Restricted to the DAO
     * Reverts if `newPrice` is 0 or > 0.1 ETH
     */
    function setMintPrice(uint256 newPrice) external restricted {
        _setMintPrice(newPrice);
    }

    function _setMintPrice(uint256 newPrice) internal {
        if (newPrice == 0 || newPrice > 0.1 ether) {
            revert InvalidValidatorTicketPrice();
        }
        emit ValidatorTicketMintPriceUpdated(_validatorTicketPrice, newPrice);
        _validatorTicketPrice = newPrice;
    }
}
