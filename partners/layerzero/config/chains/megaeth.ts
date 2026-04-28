import { CustomChainConfig } from '../types'

// Custom endpoint ID for MegaETH (not in official lz-definitions yet)
export const MEGAETH_V2_MAINNET = 30398

/**
 * MegaETH Mainnet configuration
 * Custom chain - LayerZero deployed but not in devtools
 */
export const megaeth: CustomChainConfig = {
    name: 'megaeth',
    chainId: 4326,
    eid: MEGAETH_V2_MAINNET,

    rpcUrl: process.env.MEGAETH_RPC_URL || 'https://mainnet.megaeth.com/rpc',
    timeout: 120000,

    explorer: {
        apiUrl: 'https://megaeth.blockscout.com/api',
        browserUrl: 'https://megaeth.blockscout.com',
        apiKey: process.env.MEGAETH_EXPLORER_API_KEY || 'megaeth',
    },

    layerzero: {
        endpointV2: '0x6F475642a6e85809B1c36Fa62763669b1b48DD5B',
        sendUln302: '0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7',
        receiveUln302: '0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043',
        executor: '0x4208D6E27538189bB48E603D6123A94b8Abe0A0b',
        dvns: {
            required: [
                '0x7decc6df3af9cfc275e25d2f9703ecf7ad800d5d', // Canary
                '0x8ede21203e062d7d1eaec11c4c72ad04cdc15658', // Horizen
                '0xeede111103535e473451311e26c3e6660b0f77e1', // Nethermind
            ],
            optional: [],
        },
    },

    wiring: {
        confirmations: 5,
        executorMaxMessageSize: 10000,
        lzReceiveGas: 250000, // MegaETH has non-typical gas consumption
    },

    contracts: {
        // pufETH OFT on MegaETH
        pufETH: '0x37D6382B6889cCeF8d6871A8b60E667115eDDBcF',
    },

    tokenType: 'OFT',
}
