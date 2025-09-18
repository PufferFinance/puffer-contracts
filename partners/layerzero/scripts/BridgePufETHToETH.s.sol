// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { pufETH } from "../contracts/pufETH.sol";
import { OFTCore } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

//Command to run:
//  forge script scripts/BridgePufETHToETH.s.sol:SendOFT --rpc-url https://rpc.hyperliquid.xyz/evm -vvvvv
contract SendOFT is Script {
    using OptionsBuilder for bytes;

    /**
     * @dev Converts an address to bytes32.
     * @param _addr The address to convert.
     * @return The bytes32 representation of the address.
     */
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    //     struct SendParam {
    //     uint32 dstEid; // Destination endpoint ID.
    //     bytes32 to; // Recipient address.
    //     uint256 amountLD; // Amount to send in local decimals.
    //     uint256 minAmountLD; // Minimum amount to send in local decimals.
    //     bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
    //     bytes composeMsg; // The composed message for the send() operation.
    //     bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
    // }

    function generateCallData(
        address oftAddress,
        address toAddress,
        uint256 _tokensToSend,
        uint32 dstEid
    ) public returns (bytes memory callData, uint256 nativeFee) {
        pufETH sourceOFT = pufETH(oftAddress);

        bytes memory _extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(65000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: addressToBytes32(toAddress),
            amountLD: _tokensToSend,
            minAmountLD: _tokensToSend,
            extraOptions: _extraOptions,
            composeMsg: "",
            oftCmd: ""
        });

        // Get the messaging fee
        MessagingFee memory fee = sourceOFT.quoteSend(sendParam, false);

        // Generate the calldata for the send function
        callData = abi.encodeWithSelector(
            OFTCore.send.selector,
            sendParam,
            fee,
            toAddress // recipient address
        );

        nativeFee = fee.nativeFee;
    }

    function run() public {
        address oftAddress = 0x37D6382B6889cCeF8d6871A8b60E667115eDDBcF; //pufETH OFT address

        uint32 dstChainId = 30101; // 30101 is the endpoint ID for the ETH chain

        // ----------TO CHANGE----------
        address toAddress = 0x1BfAec64abFddcC8c5dA134880d1E71f3E03689E; //recipient address
        uint256 _tokensToSend = 0.007 ether; //amount to send; you can also decimal ether like 1.2 ether or 100 ether or
        // ----------TO CHANGE----------

        (bytes memory callData, uint256 fee) = generateCallData(oftAddress, toAddress, _tokensToSend, dstChainId);
        console.log("Use the below command for cast call:");
        console.log(
            string.concat(
                "cast call ",
                toHexString(uint160(oftAddress)),
                " ",
                toHexString(bytes(callData)),
                " --value ",
                vm.toString(fee),
                " --rpc-url https://rpc.hyperliquid.xyz/evm --ledger --hd-path 'm/44'/60'/21'/0/0'"
            )
        );
    }

    // Helper functions to convert uint160 and bytes to hex strings

    function toHexString(uint160 value) internal pure returns (string memory) {
        return string.concat("0x", _toHexString(value, 20));
    }

    function toHexString(bytes memory value) internal pure returns (string memory) {
        return string.concat("0x", _toHexString(value));
    }

    function _toHexString(uint160 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length);
        for (uint256 i = 2 * length; i > 0; i--) {
            buffer[i - 1] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }

    function _toHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * data.length);
        for (uint256 i = 0; i < data.length; i++) {
            uint8 value = uint8(data[i]);
            buffer[2 * i] = _HEX_SYMBOLS[value >> 4];
            buffer[2 * i + 1] = _HEX_SYMBOLS[value & 0xf];
        }
        return string(buffer);
    }

    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
}
