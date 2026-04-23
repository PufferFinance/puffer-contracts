import { CustomChainConfig } from '../types'
import { EndpointId } from '@layerzerolabs/lz-definitions'

export const linea: CustomChainConfig = {
    name: 'linea',
    chainId: 59144,
    eid: EndpointId.ZKCONSENSYS_V2_MAINNET, // 30183

    rpcUrl: process.env.LINEA_RPC_URL || 'https://linea-rpc.publicnode.com',
    timeout: 120000,

    explorer: {
        apiUrl: 'https://api.lineascan.build',
        browserUrl: 'https://lineascan.build',
        apiKey: process.env.LINEA_EXPLORER_API_KEY,
    },

    layerzero: {
        endpointV2: '0x1a44076050125825900e736c501f859c50fE728c',
        sendUln302: '0x32042142DD551b4EbE17B6FEd53131dd4b4eEa06',
        receiveUln302: '0xE22ED54177CE1148C557de74E4873619e6c6b205',
        executor: '0x0408804C5dcD9796F22558464E6fE5bDdF16A7c7',
        dvns: {
            required: [
                '0x0b239476a771834d846cb505817bac3c391c338a', // P2P
                '0x7fe673201724925b5c477d4e1a4bd3e954688cf5', // Horizen
                '0xda63525a0fc42bcc2cad1dd28708d5ed11849347', // Canary
                '0xdd7b5e1db4aafd5c8ec3b764efb8ed265aa5445b', // Nethermind
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
        // pufETH OFT on Linea
        pufETH: '0x37D6382B6889cCeF8d6871A8b60E667115eDDBcF',
    },

    tokenType: 'OFT',
}
