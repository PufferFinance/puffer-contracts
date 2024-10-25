// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IGuardianModule } from "./interface/IGuardianModule.sol";
import { IPufferOracleV2 } from "./interface/IPufferOracleV2.sol";
//solhint-disable-next-line no-unused-import
import { IPufferOracle } from "./interface/IPufferOracle.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

/**
 * @title PufferOracle
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PufferOracleV2 is IPufferOracleV2, AccessManaged {
    /**
     * @dev Burst threshold
     */
    uint256 internal constant _BURST_THRESHOLD = 22;

    /**
     * @notice Guardian Module
     */
    IGuardianModule public immutable GUARDIAN_MODULE;

    /**
     * @notice Puffer Vault
     */
    address payable public immutable PUFFER_VAULT;

    /**
     * @dev Number of active Puffer validators
     * Slot 0
     */
    uint256 internal _numberOfActivePufferValidators;

    /**
     * @dev Total number of Validators
     * Slot 1
     */
    uint256 internal _totalNumberOfValidators;
    /**
     * @dev Epoch number of the update
     * Slot 2
     */
    uint256 internal _epochNumber;

    /**
     * @dev Price in wei to mint one Validator Ticket
     * Slot 3
     */
    uint256 internal _validatorTicketPrice;

    constructor(IGuardianModule guardianModule, address payable vault, address accessManager)
        AccessManaged(accessManager)
    {
        GUARDIAN_MODULE = guardianModule;
        PUFFER_VAULT = vault;
        _totalNumberOfValidators = 927122; // Oracle will be updated with the correct value
        _epochNumber = 268828; // Oracle will be updated with the correct value
        _setMintPrice(0.01 ether);
    }

    /**
     * @notice Exits the validator from the Beacon chain
     * @dev Restricted to PufferProtocol contract
     */
    function exitValidators(uint256 numberOfExits) public restricted {
        // nosemgrep basic-arithmetic-underflow
        _numberOfActivePufferValidators -= numberOfExits;
        emit NumberOfActiveValidators(_numberOfActivePufferValidators);
    }

    /**
     * @notice Increases the locked eth amount amount on the Oracle by 32 ETH
     * It is called when the Beacon chain receives a new deposit from PufferProtocol
     * The PufferVault balance is decreased by the same amount
     * @dev Restricted to PufferProtocol contract
     */
    function provisionNode() external restricted {
        unchecked {
            ++_numberOfActivePufferValidators;
        }
        emit NumberOfActiveValidators(_numberOfActivePufferValidators);
    }

    /**
     * @notice Updates the price to mint VT
     * @param newPrice The new price to set for minting VT
     * @dev Restricted to the DAO
     */
    function setMintPrice(uint256 newPrice) external restricted {
        _setMintPrice(newPrice);
    }

    /**
     * @notice Updates the total number of validators
     * @param newTotalNumberOfValidators The new number of validators
     */
    function setTotalNumberOfValidators(
        uint256 newTotalNumberOfValidators,
        uint256 epochNumber,
        bytes[] calldata guardianEOASignatures
    ) external restricted {
        if (epochNumber <= _epochNumber) {
            revert InvalidUpdate();
        }
        GUARDIAN_MODULE.validateTotalNumberOfValidators(newTotalNumberOfValidators, epochNumber, guardianEOASignatures);
        emit TotalNumberOfValidatorsUpdated(_totalNumberOfValidators, newTotalNumberOfValidators, epochNumber);
        _totalNumberOfValidators = newTotalNumberOfValidators;
        _epochNumber = epochNumber;
    }

    /**
     * @inheritdoc IPufferOracle
     */
    function getLockedEthAmount() external view returns (uint256) {
        return _numberOfActivePufferValidators * 32 ether;
    }

    /**
     * @inheritdoc IPufferOracleV2
     */
    function getTotalNumberOfValidators() external view returns (uint256) {
        return _totalNumberOfValidators;
    }

    /**
     * @inheritdoc IPufferOracle
     */
    function isOverBurstThreshold() external view returns (bool) {
        return ((_numberOfActivePufferValidators * 100 / _totalNumberOfValidators) > _BURST_THRESHOLD);
    }

    /**
     * @inheritdoc IPufferOracle
     */
    function getValidatorTicketPrice() external view returns (uint256) {
        return _validatorTicketPrice;
    }

    /**
     * @inheritdoc IPufferOracleV2
     */
    function getNumberOfActiveValidators() external view returns (uint256) {
        return _numberOfActivePufferValidators;
    }

    function _setMintPrice(uint256 newPrice) internal {
        emit ValidatorTicketMintPriceUpdated(_validatorTicketPrice, newPrice);
        _validatorTicketPrice = newPrice;
    }
}
