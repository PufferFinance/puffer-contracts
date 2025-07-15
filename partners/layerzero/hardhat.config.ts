// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import 'hardhat-deploy'
import 'hardhat-contract-sizer'
import '@nomiclabs/hardhat-ethers'
import '@layerzerolabs/toolbox-hardhat'
import { HardhatUserConfig, HttpNetworkAccountsUserConfig } from 'hardhat/types'

import { EndpointId } from '@layerzerolabs/lz-definitions'
import '@nomicfoundation/hardhat-verify'
import './tasks/send'
import './type-extensions'

// Set your preferred authentication method
//
// If you prefer using a mnemonic, set a MNEMONIC environment variable
// to a valid mnemonic
const MNEMONIC = process.env.MNEMONIC

// If you prefer to be authenticated using a private key, set a PRIVATE_KEY environment variable
const PRIVATE_KEY = process.env.PRIVATE_KEY

const accounts: HttpNetworkAccountsUserConfig | undefined = MNEMONIC
    ? { mnemonic: MNEMONIC }
    : PRIVATE_KEY
      ? [PRIVATE_KEY]
      : undefined

if (accounts == null) {
    console.warn(
        'Could not find MNEMONIC or PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example.'
    )
}

const config: HardhatUserConfig = {
    paths: {
        cache: 'cache/hardhat',
    },
    solidity: {
        compilers: [
            {
                version: '0.8.22',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        // the network you are deploying to or are already on
        // Ethereum Mainnet (EID=30101)
        'ethereum-mainnet': {
            eid: EndpointId.ETHEREUM_V2_MAINNET,
            url: 'https://mainnet.gateway.tenderly.co/4T8uVUWd2hhleYHsoWNQCp',
            accounts,
        },
        // another network you want to connect to
        // 'bsc-mainnet': {
        //     eid: EndpointId.BSC_V2_MAINNET,
        //     url: 'https://bsc-dataseed.binance.org',
        //     accounts,
        // },
        'hyperliquid-mainnet': {
            eid: EndpointId.HYPERLIQUID_V2_MAINNET,
            url: 'https://rpc.hyperliquid.xyz/evm',
            accounts,
        },
        'tac-mainnet': {
            eid: EndpointId.TAC_V2_MAINNET,
            url: 'https://rpc.tac.build',
            accounts,
        },
        hardhat: {
            // Need this for testing because TestHelperOz5.sol is exceeding the compiled contract size limit
            allowUnlimitedContractSize: true,
        },
        // the network you are deploying to or are already on
    },
    namedAccounts: {
        deployer: {
            default: 0, // wallet address of index[0], of the mnemonic in .env
        },
    },
    etherscan: {
        apiKey: {
            // Ethereum
            mainnet: 'VN5BY6VUXDAHEBK7XQHWQUVNPEPW3IVQSY',
            // Hyperliquid
            'hyperevm-mainnet': 'empty',
            // TAC
            'tac-mainnet': 'empty',
        },
        customChains: [
            {
                network: 'hyperevm-mainnet',
                chainId: 999,
                urls: {
                    apiURL: 'https://www.hyperscan.com/api',
                    browserURL: 'https://www.hyperscan.com',
                },
            },
            {
                network: 'tac-mainnet',
                chainId: 239,
                urls: {
                    apiURL: 'https://explorer.tac.build/api',
                    browserURL: 'https://explorer.tac.build',
                },
            },
        ],
        // customChains: [
        //     {
        //         network: 'bsc',
        //         chainId: 56,
        //         urls: {
        //             apiURL: 'https://api.bscscan.com/api',
        //             browserURL: 'https://bscscan.com',
        //         },
        //     },
        //     {
        //         network: 'bscTestnet',
        //         chainId: 97,
        //         urls: {
        //             apiURL: 'https://api-testnet.bscscan.com/api',
        //             browserURL: 'https://testnet.bscscan.com',
        //         },
        //     },
        // Add other custom chains as needed
        // ],
    },
}

export default config
