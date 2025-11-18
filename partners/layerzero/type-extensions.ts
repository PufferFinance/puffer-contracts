import 'hardhat/types/config'
import { EndpointId } from '@layerzerolabs/lz-definitions'

// Define custom endpoint IDs for networks not yet in LayerZero's official definitions
export const MONAD_V2_MAINNET = 30390 as EndpointId

interface OftAdapterConfig {
    tokenAddress: string
}

declare module 'hardhat/types/config' {
    interface HardhatNetworkUserConfig {
        oftAdapter?: never
    }

    interface HardhatNetworkConfig {
        oftAdapter?: never
    }

    interface HttpNetworkUserConfig {
        oftAdapter?: OftAdapterConfig
    }

    interface HttpNetworkConfig {
        oftAdapter?: OftAdapterConfig
    }
}
