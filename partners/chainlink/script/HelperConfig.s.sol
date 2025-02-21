// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        uint64 chainSelector;
        address router;
        address rmnProxy;
        address tokenAdminRegistry;
        address registryModuleOwnerCustom;
        address link;
        uint256 confirmations;
        string nativeCurrencySymbol;
    }

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getEthereumSepoliaConfig();
        } else if (block.chainid == 421614) {
            activeNetworkConfig = getArbitrumSepolia();
        } else if (block.chainid == 43113) {
            activeNetworkConfig = getAvalancheFujiConfig();
        } else if (block.chainid == 84532) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else if (block.chainid == 1868) {
            activeNetworkConfig = getSoneiumConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getEthereumConfig();
        } else if (block.chainid == 42161) {
            activeNetworkConfig = getArbitrumConfig();
        }
    }

    function getArbitrumConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory arbitrumConfig = NetworkConfig({
            chainSelector: 4949039107694359620,
            router: 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8 ,
            rmnProxy: 0xC311a21e6fEf769344EB1515588B9d535662a145,
            tokenAdminRegistry: 0x39AE1032cF4B334a1Ed41cdD0833bdD7c7E7751E ,
            registryModuleOwnerCustom: 0x1f1df9f7fc939E71819F766978d8F900B816761b,
            link: 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4,
            confirmations: 2,
            nativeCurrencySymbol: "ETH"
        });
        return arbitrumConfig;
    }
    function getSoneiumConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory soneiumConfig = NetworkConfig({
            chainSelector: 12505351618335765396,
            router: 0x8C8B88d827Fe14Df2bc6392947d513C86afD6977,
            rmnProxy: 0x3117f515D763652A32d3D6D447171ea7c9d57218,
            tokenAdminRegistry: 0x5ba21F6824400B91F232952CA6d7c8875C1755a4,
            // Not updated by Chainlink; Later check directory for the correct address
            registryModuleOwnerCustom: 0x1d0B6B3ef94dD6A68b7E16bd8B01fca9EA8e3d6E,
            link: 0x32D8F819C8080ae44375F8d383Ffd39FC642f3Ec,
            confirmations: 2,
            nativeCurrencySymbol: "ETH"
        });
        return soneiumConfig;
    }

    function getEthereumConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory ethereumConfig = NetworkConfig({
            chainSelector: 5009297550715157269,
            router: 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D,
            rmnProxy: 0x411dE17f12D1A34ecC7F45f49844626267c75e81,
            tokenAdminRegistry: 0xb22764f98dD05c789929716D677382Df22C05Cb6,
            registryModuleOwnerCustom: 0x4855174E9479E211337832E109E7721d43A4CA64,
            link: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            confirmations: 2,
            nativeCurrencySymbol: "ETH"
        });
        return ethereumConfig;
    }

    function getEthereumSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory ethereumSepoliaConfig = NetworkConfig({
            chainSelector: 16015286601757825753,
            router: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
            rmnProxy: 0xba3f6251de62dED61Ff98590cB2fDf6871FbB991,
            tokenAdminRegistry: 0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82,
            registryModuleOwnerCustom: 0x62e731218d0D47305aba2BE3751E7EE9E5520790,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            confirmations: 2,
            nativeCurrencySymbol: "ETH"
        });
        return ethereumSepoliaConfig;
    }

    function getArbitrumSepolia() public pure returns (NetworkConfig memory) {
        NetworkConfig memory arbitrumSepoliaConfig = NetworkConfig({
            chainSelector: 3478487238524512106,
            router: 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165,
            rmnProxy: 0x9527E2d01A3064ef6b50c1Da1C0cC523803BCFF2,
            tokenAdminRegistry: 0x8126bE56454B628a88C17849B9ED99dd5a11Bd2f,
            registryModuleOwnerCustom: 0xE625f0b8b0Ac86946035a7729Aba124c8A64cf69,
            link: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E,
            confirmations: 2,
            nativeCurrencySymbol: "ETH"
        });
        return arbitrumSepoliaConfig;
    }

    function getAvalancheFujiConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory avalancheFujiConfig = NetworkConfig({
            chainSelector: 14767482510784806043,
            router: 0xF694E193200268f9a4868e4Aa017A0118C9a8177,
            rmnProxy: 0xAc8CFc3762a979628334a0E4C1026244498E821b,
            tokenAdminRegistry: 0xA92053a4a3922084d992fD2835bdBa4caC6877e6,
            registryModuleOwnerCustom: 0x97300785aF1edE1343DB6d90706A35CF14aA3d81,
            link: 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846,
            confirmations: 2,
            nativeCurrencySymbol: "AVAX"
        });
        return avalancheFujiConfig;
    }

    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory baseSepoliaConfig = NetworkConfig({
            chainSelector: 10344971235874465080,
            router: 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93,
            rmnProxy: 0x99360767a4705f68CcCb9533195B761648d6d807,
            tokenAdminRegistry: 0x736D0bBb318c1B27Ff686cd19804094E66250e17,
            registryModuleOwnerCustom: 0x8A55C61227f26a3e2f217842eCF20b52007bAaBe,
            link: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410,
            confirmations: 2,
            nativeCurrencySymbol: "ETH"
        });
        return baseSepoliaConfig;
    }
}
