// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title LibBeaconchainContract
 * @dev Copied from the deposit contract
 *         https://github.com/ethereum/consensus-specs/blob/dev/solidity_deposit_contract/deposit_contract.sol
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
library LibBeaconchainContract {
    /**
     * @notice Returns the deposit data root. We assume that the deposit amount is 32 ETH
     * @param pubKey is the public key
     * @param signature is the signature
     * @param withdrawalCredentials is the withdrawal credentials
     * @return the deposit data root
     */
    function getDepositDataRoot(bytes calldata pubKey, bytes calldata signature, bytes calldata withdrawalCredentials)
        external
        pure
        returns (bytes32)
    {
        bytes32 pubKeyRoot = sha256(abi.encodePacked(pubKey, bytes16(0)));
        bytes32 signatureRoot = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(signature[:64])), sha256(abi.encodePacked(signature[64:], bytes32(0)))
            )
        );
        return sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(pubKeyRoot, withdrawalCredentials)),
                sha256(
                    abi.encodePacked(
                        hex"0040597307000000000000000000000000000000000000000000000000000000", signatureRoot
                    )
                )
            )
        );
    }

    /**
     * @notice Returns the deposit data root for variable ETH amounts (Pectra support)
     * @param pubKey The validator public key
     * @param signature The validator signature
     * @param withdrawalCredentials The withdrawal credentials
     * @param amount The deposit amount in wei (must be 32-2048 ETH in 1 gwei increments)
     * @return The deposit data root
     */
    function getDepositDataRootWithAmount(
        bytes calldata pubKey,
        bytes calldata signature,
        bytes calldata withdrawalCredentials,
        uint256 amount
    ) external pure returns (bytes32) {
        bytes32 pubKeyRoot = sha256(abi.encodePacked(pubKey, bytes16(0)));
        bytes32 signatureRoot = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(signature[:64])), sha256(abi.encodePacked(signature[64:], bytes32(0)))
            )
        );

        // Convert amount to little-endian Gwei bytes
        bytes memory amountBytes = _toLittleEndianGwei(amount);

        return sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(pubKeyRoot, withdrawalCredentials)),
                sha256(abi.encodePacked(amountBytes, signatureRoot))
            )
        );
    }

    /**
     * @dev Converts wei amount to 32-byte little-endian Gwei representation
     * @param amountWei The amount in wei
     * @return result 32-byte little-endian representation
     */
    function _toLittleEndianGwei(uint256 amountWei) internal pure returns (bytes memory) {
        uint64 amountGwei = uint64(amountWei / 1 gwei);
        bytes memory result = new bytes(32);

        // Write as little-endian (least significant byte first)
        for (uint256 i = 0; i < 8; i++) {
            result[i] = bytes1(uint8(amountGwei >> (i * 8)));
        }
        // Remaining 24 bytes are already zero

        return result;
    }
}
