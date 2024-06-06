// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title ValidatorTicketStorage
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
abstract contract ValidatorTicketStorage {
    /**
     * @custom:storage-location erc7201:ValidatorTicket.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct ValidatorTicket {
        /**
         * @dev Protocol fee rate, can be updated by governance (10,000 = 100%, 100 = 1%)
         * Slot 0
         */
        uint128 protocolFeeRate;
        /**
         * @dev Guardians fee rate, can be updated by governance (10,000 = 100%, 100 = 1%)
         * Slot 0
         */
        uint128 guardiansFeeRate;
    }

    /**
     * @dev Storage slot location for ValidatorTicket
     * @custom:storage-location erc7201:ValidatorTicket.storage
     * keccak256(abi.encode(uint256(keccak256("ValidatorTicket.storage")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant _VALIDATOR_TICKET_STORAGE =
        0x522b25b4b3844af9be07fc1b83a538fd31925481b968b15976cafed863007000;

    function _getValidatorTicketStorage() internal pure returns (ValidatorTicket storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _VALIDATOR_TICKET_STORAGE
        }
    }
}
