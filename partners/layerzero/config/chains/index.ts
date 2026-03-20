import { CustomChainConfig } from '../types'
import { ethereum } from './ethereum'
import { monad, MONAD_V2_MAINNET } from './monad'
import { megaeth, MEGAETH_V2_MAINNET } from './megaeth'

// Re-export custom endpoint IDs
export { MONAD_V2_MAINNET, MEGAETH_V2_MAINNET }

// All chain configs indexed by network name
export const chainConfigs: Record<string, CustomChainConfig> = {
    'ethereum-mainnet': ethereum,
    ethereum: ethereum, // Alias
    monad: monad,
    megaeth: megaeth,
}

// Get config by name (case-insensitive)
export function getChainConfig(name: string): CustomChainConfig | undefined {
    const normalizedName = name.toLowerCase().replace(/-/g, '')
    for (const [key, config] of Object.entries(chainConfigs)) {
        if (key.toLowerCase().replace(/-/g, '') === normalizedName) {
            return config
        }
    }
    return undefined
}

// List all available chains
export function listChains(): string[] {
    return Object.keys(chainConfigs)
}

// Export individual configs for direct import
export { ethereum, monad, megaeth }
