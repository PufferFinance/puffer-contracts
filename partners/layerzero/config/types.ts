import { EndpointId } from '@layerzerolabs/lz-definitions'

/**
 * Complete chain configuration for custom (exotic) chain deployments
 * All chain-specific data in one place: RPC, explorer, LZ infrastructure
 */
export interface CustomChainConfig {
    // Basic chain info
    name: string
    chainId: number
    eid: EndpointId | number // LayerZero endpoint ID

    // Network connectivity
    rpcUrl: string
    timeout?: number // Transaction timeout in ms (default: 120000)

    // Block explorer (for verification)
    explorer?: {
        apiUrl: string
        browserUrl: string
        apiKey?: string // Optional API key for explorer
    }

    // LayerZero infrastructure addresses
    layerzero: {
        endpointV2: string
        sendUln302: string
        receiveUln302: string
        executor: string
        dvns: {
            required: string[] // Required DVNs (at least 1)
            optional?: string[] // Optional DVNs
            threshold?: number // Threshold for optional DVNs
        }
    }

    // Wiring configuration
    wiring: {
        confirmations: number // Block confirmations for ULN config
        executorMaxMessageSize?: number // Default: 10000
        lzReceiveGas?: number // Gas for lzReceive execution (default: 80000)
    }

    // Contract deployment info (filled after deployment)
    contracts?: {
        pufETH?: string // OFT contract address
        pufETHAdapter?: string // OFTAdapter contract address
        PUFFER?: string // PUFFER OFT address
        PUFFERAdapter?: string // PUFFER OFTAdapter address
    }

    // Token being deployed (pufETH or PUFFER)
    // This determines which contract type to use
    tokenType?: 'OFT' | 'OFTAdapter'
}

/**
 * State tracking for resume functionality
 */
export type WiringStepStatus = 'pending' | 'completed' | 'skipped'

export interface WiringStep {
    name: string
    status: WiringStepStatus
    txHash?: string
    calldata?: string // For multisig transactions
    timestamp?: number
    error?: string
}

export interface WiringState {
    token: string // pufETH or PUFFER
    sourceChain: string
    destChain: string
    createdAt: number
    updatedAt: number
    steps: {
        // Deployment
        deploy_dest?: WiringStep

        // Source chain wiring (e.g., Ethereum)
        source_setPeer?: WiringStep
        source_setEnforcedOptions?: WiringStep
        source_setSendConfig?: WiringStep
        source_setReceiveConfig?: WiringStep

        // Destination chain wiring (e.g., Monad)
        dest_setPeer?: WiringStep
        dest_setEnforcedOptions?: WiringStep
        dest_setSendConfig?: WiringStep
        dest_setReceiveConfig?: WiringStep
    }
}

/**
 * Safe batch transaction format (Gnosis Safe)
 */
export interface SafeTransaction {
    to: string
    value: string
    data: string
    operation?: number // 0 = Call, 1 = DelegateCall
}

export interface SafeBatch {
    version: string
    chainId: string
    createdAt: number
    meta: {
        name: string
        description: string
    }
    transactions: SafeTransaction[]
}

/**
 * Output from the wiring task
 */
export interface WiringOutput {
    success: boolean
    sourceChain: {
        network: string
        executed: boolean
        txHashes?: string[]
        calldata?: {
            transactions: Array<{
                to: string
                data: string
                description: string
            }>
            safeBatch?: SafeBatch
        }
    }
    destChain: {
        network: string
        executed: boolean
        txHashes?: string[]
        calldata?: {
            transactions: Array<{
                to: string
                data: string
                description: string
            }>
            safeBatch?: SafeBatch
        }
    }
}
