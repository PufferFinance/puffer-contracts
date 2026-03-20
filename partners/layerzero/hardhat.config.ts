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

import '@nomicfoundation/hardhat-verify'
import './tasks/send'
import './tasks/customWire'
import './type-extensions'

// Import chain configs for dynamic network setup
import { chainConfigs } from './config'

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

// Build networks from chain configs
function buildNetworksFromConfig(): Record<string, any> {
    const networks: Record<string, any> = {}
    for (const [name, config] of Object.entries(chainConfigs)) {
        // Skip aliases (e.g., 'ethereum' alias for 'ethereum-mainnet')
        if (name === 'ethereum') continue

        networks[name] = {
            eid: config.eid,
            url: config.rpcUrl,
            accounts,
            timeout: config.timeout || 120000,
        }
    }
    return networks
}

// Build custom chains for etherscan verification
function buildCustomChains(): Array<{ network: string; chainId: number; urls: { apiURL: string; browserURL: string } }> {
    const customChains: Array<{ network: string; chainId: number; urls: { apiURL: string; browserURL: string } }> = []
    for (const [name, config] of Object.entries(chainConfigs)) {
        // Skip aliases and chains without explorer config
        if (name === 'ethereum' || !config.explorer) continue

        customChains.push({
            network: name,
            chainId: config.chainId,
            urls: {
                apiURL: config.explorer.apiUrl,
                browserURL: config.explorer.browserUrl,
            },
        })
    }
    return customChains
}

// Build API keys for etherscan verification
function buildApiKeys(): Record<string, string> {
    const apiKeys: Record<string, string> = {}
    for (const [name, config] of Object.entries(chainConfigs)) {
        if (name === 'ethereum' || !config.explorer?.apiKey) continue
        apiKeys[name] = config.explorer.apiKey
    }
    // Add default etherscan key
    if (process.env.ETHERSCAN_API_KEY) {
        apiKeys['ethereum-mainnet'] = process.env.ETHERSCAN_API_KEY
    }
    return apiKeys
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
        // Networks are loaded from config/chains/*.ts
        // To add a new chain, create a config file in config/chains/
        ...buildNetworksFromConfig(),

        // Hardhat local network for testing
        hardhat: {
            allowUnlimitedContractSize: true,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0, // wallet address of index[0], of the mnemonic in .env
        },
    },
    sourcify: {
        enabled: true,
        apiUrl: 'https://sourcify-api-monad.blockvision.org',
        browserUrl: 'https://testnet.monadexplorer.com',
    },
    etherscan: {
        enabled: true,
        // API keys loaded from chain configs (set via env vars)
        apiKey: buildApiKeys(),
        // Custom chains loaded from config/chains/*.ts
        customChains: buildCustomChains(),
    },
}

export default config
