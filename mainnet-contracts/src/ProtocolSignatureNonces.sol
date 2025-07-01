// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title ProtocolSignatureNonces
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 * @dev Abstract contract for managing protocol signatures with selector-based nonces and deadline support.
 *
 * This contract implements a selector-based nonce system to prevent DOS attacks through nonce manipulation.
 * Each function can have its own nonce space using a unique selector, preventing cross-function nonce conflicts.
 *
 * Key security features:
 * - Selector-based nonces prevent DOS attacks between different operations
 * - Deadline support for signature expiration (recommended implementation)
 * - Nonce validation to ensure proper signature ordering
 */
abstract contract ProtocolSignatureNonces {
    /**
     * @dev The nonce used for an `account` is not the expected current nonce.
     * @param selector The function selector that determines the nonce space
     * @param account The account whose nonce was invalid
     * @param currentNonce The current expected nonce for the account
     */
    error InvalidAccountNonce(bytes32 selector, address account, uint256 currentNonce);

    struct ProtocolSignatureNoncesStorage {
        /**
         * @dev Mapping from function selector to account to nonce value.
         * This creates separate nonce spaces for different operations,
         * preventing cross-function nonce manipulation attacks.
         */
        mapping(bytes32 selector => mapping(address account => uint256)) _nonces;
    }

    // keccak256(abi.encode(uint256(keccak256("ProtocolSignatureNoncesStorageLocation")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ProtocolSignatureNoncesStorageLocation =
        0xbaa308cee87141dd88d1ecc2d7cbf7f5fef8a56b897e48c821339feb34e04200;

    /**
     * @dev Returns the storage pointer for nonces.
     * @return $ The storage pointer to ProtocolSignatureNoncesStorage
     */
    function _getProtocolSignatureNoncesStorage() private pure returns (ProtocolSignatureNoncesStorage storage $) {
        assembly {
            $.slot := ProtocolSignatureNoncesStorageLocation
        }
    }

    /**
     * @dev Returns the next unused nonce for an address in a specific function context.
     * @param selector The function selector that determines the nonce space
     * @param owner The address to get the nonce for
     * @return The current nonce value for the owner in the specified function context
     */
    function nonces(bytes32 selector, address owner) public view virtual returns (uint256) {
        ProtocolSignatureNoncesStorage storage $ = _getProtocolSignatureNoncesStorage();
        return $._nonces[selector][owner];
    }

    /**
     * @dev Consumes a nonce for a specific function context.
     * Returns the current value and increments nonce.
     * @param selector The function selector that determines the nonce space
     * @param owner The address whose nonce to consume
     * @return The current nonce value before incrementing
     *
     * @dev This function increments the nonce atomically, ensuring
     * that each nonce can only be used once per function context.
     * The nonce cannot be decremented or reset, preventing replay attacks.
     */
    function _useNonce(bytes32 selector, address owner) internal virtual returns (uint256) {
        ProtocolSignatureNoncesStorage storage $ = _getProtocolSignatureNoncesStorage();
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        unchecked {
            // It is important to do x++ and not ++x here.
            return $._nonces[selector][owner]++;
        }
    }

    /**
     * @dev Same as {_useNonce} but checking that `nonce` is the next valid for `owner`.
     * @param selector The function selector that determines the nonce space
     * @param owner The address whose nonce to validate and consume
     * @param nonce The expected nonce value
     *
     * @dev This function validates that the provided nonce matches the expected
     * current nonce before consuming it. This prevents replay attacks and
     * ensures proper signature ordering.
     *
     * @dev Reverts with InvalidAccountNonce if the nonce doesn't match.
     */
    function _useCheckedNonce(bytes32 selector, address owner, uint256 nonce) internal virtual {
        uint256 current = _useNonce(selector, owner);
        if (nonce != current) {
            revert InvalidAccountNonce(selector, owner, current);
        }
    }
}
