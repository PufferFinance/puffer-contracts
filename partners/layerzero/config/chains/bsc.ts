import { CustomChainConfig } from '../types'
import { EndpointId } from '@layerzerolabs/lz-definitions'

export const bsc: CustomChainConfig = {
    name: 'bsc',
    chainId: 56,
    eid: EndpointId.BSC_V2_MAINNET, // 30102

    rpcUrl: process.env.BSC_RPC_URL || 'https://public-bsc-mainnet.fastnode.io',
    timeout: 120000,

    explorer: {
        apiUrl: 'https://api.bscscan.com',
        browserUrl: 'https://bscscan.com',
        apiKey: process.env.BSC_EXPLORER_API_KEY,
    },

    layerzero: {
        endpointV2: '0x1a44076050125825900e736c501f859c50fE728c',
        sendUln302: '0x9F8C645f2D0b2159767Bd6E0839DE4BE49e823DE',
        receiveUln302: '0xB217266c3A98C8B2709Ee26836C98cf12f6cCEC1',
        executor: '0x3ebD570ed38B1b3b4BC886999fcF507e9D584859',
        dvns: {
            required: [
                '0x247624e2143504730aec22912ed41f092498bef2', // Horizen
                '0x31f748a368a893bdb5abb67ec95f232507601a73', // Nethermind
                '0xfa9ba83c102283958b997adc8b44ed3a3cdb5dda', // Canary
                '0x439264fb87581a70bb6d7befd16b636521b0ad2d', // P2P
            ],
            optional: [],
        },
    },

    wiring: {
        confirmations: 5,
        executorMaxMessageSize: 10000,
        lzReceiveGas: 80000,
    },

    contracts: {
        // PUFFER OFT on BSC
        PUFFER: '0x87d00066cf131ff54b72b134a217d5401e5392b6',
    },

    tokenType: 'OFT',
}
