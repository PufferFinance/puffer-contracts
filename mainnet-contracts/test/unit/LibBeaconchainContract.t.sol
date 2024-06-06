// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { LibBeaconchainContract } from "../../src/LibBeaconchainContract.sol";

/**
 * Test that compares the output of an old version and a new one
 */
contract LibBeaconChainTest is Test {
    function testUpdatedVersion(bytes32 pubKeyPart) external view {
        bytes memory randomSignature =
            hex"8aa088146c8c6ca6d8ad96648f20e791be7c449ce7035a6bd0a136b8c7b7867f730428af8d4a2b69658bfdade185d6110b938d7a59e98d905e922d53432e216dc88c3384157d74200d3f2de51d31737ce19098ff4d4f54f77f0175e23ac98da5";

        bytes32 newVersion = LibBeaconchainContract.getDepositDataRoot(
            _getPubKey(pubKeyPart), randomSignature, _getWithdrawalCredentials()
        );
        bytes32 oldVersion = LibBeaconchainContractOld.getDepositDataRoot(
            _getPubKey(pubKeyPart), randomSignature, _getWithdrawalCredentials()
        );
        assertEq(newVersion, oldVersion, "mismatch");
    }

    function _getPubKey(bytes32 pubKeyPart) internal pure returns (bytes memory) {
        return bytes.concat(abi.encodePacked(pubKeyPart), bytes16(""));
    }

    function _getWithdrawalCredentials() internal view returns (bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }
}

/**
 * Old version of the contract that worked, copied form the repo before the changes
 * https://github.com/PufferFinance/PufferPool/blob/8e9f54229dc793d1f2516ca25d6360804bd6a115/src/LibBeaconchainContract.sol
 */
library LibBeaconchainContractOld {
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
                sha256(abi.encodePacked(_toLittleEndian64(uint64(32 ether / 1 gwei)), bytes24(0), signatureRoot))
            )
        );
    }

    function _toLittleEndian64(uint64 value) private pure returns (bytes memory ret) {
        // Copied https://github.com/ethereum/consensus-specs/blob/b04430332ec190774f4dfc039de6e83afe3327ee/solidity_deposit_contract/deposit_contract.sol#L165
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }
}
