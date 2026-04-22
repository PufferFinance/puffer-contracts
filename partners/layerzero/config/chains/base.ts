import { CustomChainConfig } from '../types'
import { EndpointId } from '@layerzerolabs/lz-definitions'

export const mychain: CustomChainConfig = {
    name: 'base',
    chainId: 8453,
    eid: EndpointId.BASE_V2_MAINNET, // 30184

    rpcUrl: process.env.BASE_RPC_URL || 'https://base.llamarpc.com',
    timeout: 120000,

    explorer: {
        apiUrl: 'https://api.basescan.org',
        browserUrl: 'https://basescan.org',
        apiKey: process.env.ETHERSCAN_API_KEY,
    },

    layerzero: {
        endpointV2: '0x1a44076050125825900e736c501f859c50fE728c',
        sendUln302: '0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2',
        receiveUln302: '0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf',
        executor: '0x2CCA08ae69E0C44b18a57Ab2A87644234dAebaE4',
        dvns: {
            required: [
                '0xa7b5189bca84cd304d8553977c7c614329750d99', // Horizen
                '0xcd37ca043f8479064e10635020c65ffc005d36f6', // Nethermind
                '0x554833698ae0fb22ecc90b01222903fd62ca4b47', // Canary
                '0x5b6735c66d97479ccd18294fc96b3084ecb2fa3f', // P2P
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
        // pufETH OFT on Base
        pufETH: '0x30D91DF53cCCf07e3a5BF6862Db8CFBe1fCB21d3',
        // PUFFER OFT on Base
        PUFFER: '0x8dA0baE597aC15fB0924713b1e3c1F624474F3E4',
    },

    tokenType: 'OFT',
}
