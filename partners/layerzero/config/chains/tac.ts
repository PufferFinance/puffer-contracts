import { CustomChainConfig } from '../types'
import { EndpointId } from '@layerzerolabs/lz-definitions'

export const tac: CustomChainConfig = {
    name: 'tac',
    chainId: 239,
    eid: EndpointId.TAC_V2_MAINNET, // 30377

    rpcUrl: process.env.TAC_RPC_URL || 'https://rpc.ankr.com/tac',
    timeout: 120000,

    explorer: {
        apiUrl: 'https://explorer.tac.build/api/v2/',
        browserUrl: 'https://explorer.tac.build',
        apiKey: process.env.TAC_EXPLORER_API_KEY,
    },

    layerzero: {
        endpointV2: '0x6F475642a6e85809B1c36Fa62763669b1b48DD5B',
        sendUln302: '0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7',
        receiveUln302: '0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043',
        executor: '0x4208D6E27538189bB48E603D6123A94b8Abe0A0b',
        dvns: {
            required: [
                '0xb19a9370d404308040a9760678c8ca28affbbb76', // Horizen
                '0x97841d4ab18e9a923322a002d5b8eb42b31ccdb5', // Nethermind
                '0x07ff86c392588254ad10f0811dbbcad45f4c7d87', // Canary
                '0x965a80dc87cec5848310e612dead84b543aef874', // P2P
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
        // pufETH OFT on TAC
        pufETH: '0x37D6382B6889cCeF8d6871A8b60E667115eDDBcF',
    },

    tokenType: 'OFT',
}
