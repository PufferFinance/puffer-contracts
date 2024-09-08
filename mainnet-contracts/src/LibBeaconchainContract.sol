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
}
