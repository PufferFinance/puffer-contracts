import * as fs from 'fs'
import * as path from 'path'
import { CustomChainConfig } from '../types'

// Duck-check: is this value a CustomChainConfig? We only look at the fields
// we need to register it — richer validation belongs in each chain file itself.
function isChainConfig(x: unknown): x is CustomChainConfig {
    if (typeof x !== 'object' || x === null) return false
    const c = x as Record<string, unknown>
    return (
        typeof c.name === 'string' &&
        typeof c.chainId === 'number' &&
        typeof c.eid === 'number' &&
        typeof c.rpcUrl === 'string' &&
        typeof c.layerzero === 'object' &&
        c.layerzero !== null
    )
}

// Auto-discover every chain config in this directory. Each file under
// config/chains/ should export a named const whose value is a CustomChainConfig;
// the variable name doesn't matter — configs are registered under their `name` field.
function loadChainConfigs(): Record<string, CustomChainConfig> {
    const configs: Record<string, CustomChainConfig> = {}

    for (const file of fs.readdirSync(__dirname)) {
        if (file.startsWith('index.')) continue
        if (file.endsWith('.d.ts')) continue
        if (!file.endsWith('.ts') && !file.endsWith('.js')) continue

        const mod = require(path.join(__dirname, file))
        for (const value of Object.values(mod)) {
            if (isChainConfig(value)) {
                configs[value.name] = value
            }
        }
    }

    return configs
}

export const chainConfigs: Record<string, CustomChainConfig> = loadChainConfigs()

// Look up a chain config by name — case-insensitive, dashes ignored.
export function getChainConfig(name: string): CustomChainConfig | undefined {
    const normalize = (s: string) => s.toLowerCase().replace(/-/g, '')
    const target = normalize(name)
    for (const [key, config] of Object.entries(chainConfigs)) {
        if (normalize(key) === target) return config
    }
    return undefined
}

// List all registered chain names, sorted for stable output.
export function listChains(): string[] {
    return Object.keys(chainConfigs).sort()
}
