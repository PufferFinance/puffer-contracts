// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperUtils} from "./utils/HelperUtils.s.sol"; // Utility functions for JSON parsing and chain info
import {HelperConfig} from "./HelperConfig.s.sol"; // Network configuration helper
import {TokenPool} from "@chainlink/contracts-ccip/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";

/**
 * forge script script/ApplyChainUpdatesMainnet.s.sol --rpc-url $MAINNET_RPC_URL
 */
contract ApplyChainUpdatesMainnet is Script {
    function run() external {
        // Get chain information
        (string memory chainName, uint256 remoteChainId) = getChainInfo();
        string memory remoteChainName = HelperUtils.getChainName(remoteChainId);

        // Get addresses
        (address poolAddress, address remotePoolAddress, address remoteTokenAddress) = getAddresses(chainName, remoteChainName);

        // Get chain selector
        uint64 remoteChainSelector = getChainSelector(remoteChainId);

        // Validate addresses and chain selector
        validateInputs(poolAddress, remotePoolAddress, remoteTokenAddress, remoteChainSelector);

        // Create and apply chain updates
        bytes memory callData = createChainUpdates(remoteChainSelector, remotePoolAddress, remoteTokenAddress);

        // Write transaction data to JSON
        writeTransactionJson(poolAddress, callData, remoteChainName);
    }

    function getChainInfo() internal view returns (string memory chainName, uint256 remoteChainId) {
        chainName = HelperUtils.getChainName(block.chainid);
        string memory configPath = string.concat(vm.projectRoot(), "/script/config.json");
        remoteChainId = HelperUtils.getUintFromJson(
            vm, configPath, string.concat(".remoteChains.", HelperUtils.uintToStr(block.chainid))
        );
    }

    function getAddresses(string memory chainName, string memory remoteChainName) 
        internal 
        view 
        returns (address poolAddress, address remotePoolAddress, address remoteTokenAddress) 
    {
        string memory root = vm.projectRoot();
        string memory localPoolPath = string.concat(root, "/script/output/deployedTokenPool_", chainName, ".json");
        string memory remotePoolPath = string.concat(root, "/script/output/deployedTokenPool_", remoteChainName, ".json");
        string memory remoteTokenPath = string.concat(root, "/script/output/deployedToken_", remoteChainName, ".json");

        poolAddress = HelperUtils.getAddressFromJson(vm, localPoolPath, string.concat(".deployedTokenPool_", chainName));
        remotePoolAddress = HelperUtils.getAddressFromJson(vm, remotePoolPath, string.concat(".deployedTokenPool_", remoteChainName));
        remoteTokenAddress = HelperUtils.getAddressFromJson(vm, remoteTokenPath, string.concat(".deployedToken_", remoteChainName));
    }

    function getChainSelector(uint256 remoteChainId) internal returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory remoteNetworkConfig = HelperUtils.getNetworkConfig(helperConfig, remoteChainId);
        return remoteNetworkConfig.chainSelector;
    }

    function validateInputs(
        address poolAddress,
        address remotePoolAddress,
        address remoteTokenAddress,
        uint64 remoteChainSelector
    ) internal pure {
        require(poolAddress != address(0), "Invalid pool address");
        require(remotePoolAddress != address(0), "Invalid remote pool address");
        require(remoteTokenAddress != address(0), "Invalid remote token address");
        require(remoteChainSelector != 0, "chainSelector is not defined for the remote chain");
    }

    function createChainUpdates(
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress
    ) internal pure returns (bytes memory) {
        address[] memory remotePoolAddresses = new address[](1);
        remotePoolAddresses[0] = remotePoolAddress;

        bytes[] memory remotePoolAddressesEncoded = new bytes[](1);
        remotePoolAddressesEncoded[0] = abi.encode(remotePoolAddress);

        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector, // Chain selector of the remote chain
            remotePoolAddresses: remotePoolAddressesEncoded, // Array of encoded addresses of the remote pools
            remoteTokenAddress: abi.encode(remoteTokenAddress), // Encoded address of the remote token
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false, // Set to true to enable outbound rate limiting
                capacity: 0, // Max tokens allowed in the outbound rate limiter
                rate: 0 // Refill rate per second for the outbound rate limiter
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false, // Set to true to enable inbound rate limiting
                capacity: 0, // Max tokens allowed in the inbound rate limiter
                rate: 0 // Refill rate per second for the inbound rate limiter
            })
        });

        uint64[] memory chainSelectorRemovals = new uint64[](0);
        return abi.encodeWithSelector(TokenPool.applyChainUpdates.selector, chainSelectorRemovals, chainUpdates);
    }

    function writeTransactionJson(address poolAddress, bytes memory callData, string memory remoteChainName) internal {
        console.log(
            "Use this calldata to apply chain updates manually by multisig on mainnet (TokenPool address: ",
            poolAddress,
            "):"
        );
        console.logBytes(callData);

        vm.writeJson(
            string.concat(
                '{"chainId": "',
                HelperUtils.uintToStr(block.chainid),
                '","transactions": [{"to": "',
                vm.toString(poolAddress),
                '","value": "0","data": "',
                vm.toString(callData),
                '"}]}'
            ),
            string.concat(
                vm.projectRoot(),
                "/script/output/chainUpdatesMainnet_",
                remoteChainName,
                ".json"
            )
        );

        console.log("----------------------------------");
        console.log("--------------OR------------------");
        console.log("Upload this file to the Safe/Den to apply the chain updates:");
        console.log(
            "Saved Safe transaction JSON to: %s",
            string.concat(
                vm.projectRoot(),
                "/script/output/chainUpdatesMainnet_",
                remoteChainName,
                ".json"
            )
        );
    }
}
