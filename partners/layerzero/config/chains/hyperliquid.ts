import { CustomChainConfig } from '../types'
import { EndpointId } from '@layerzerolabs/lz-definitions'

export const hyperliquid: CustomChainConfig = {
    name: 'hyperliquid',
    chainId: 999,
    eid: EndpointId.HYPERLIQUID_V2_MAINNET, // 30367

    rpcUrl: process.env.HYPERLIQUID_RPC_URL || 'https://hyperliquid.drpc.org',
    timeout: 120000,

    explorer: {
        apiUrl: 'https://api.hyperevmscan.io/',
        browserUrl: 'https://hyperevmscan.io/',
        apiKey: process.env.HYPERLIQUID_EXPLORER_API_KEY,
    },

    layerzero: {
        endpointV2: '0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9',
        sendUln302: '0xfd76d9CB0Bac839725aB79127E7411fe71b1e3CA',
        receiveUln302: '0x7cacBe439EaD55fa1c22790330b12835c6884a91',
        executor: '0x41Bdb4aa4A63a5b2Efc531858d3118392B1A1C3d',
        dvns: {
            required: [
                '0xbb83ecf372cbb6daa629ea9a9a53bec6d601f229', // Horizen
                '0x8e49ef1dfae17e547ca0e7526ffda81fbaca810a', // Nethermind
                '0x83342ec538df0460e730a8f543fe63063e2d44c4', // Canary
                '0xc7423626016bc40375458bc0277f28681ec91c8e', // P2P
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
        // pufETH OFT on HyperEVM
        pufETH: '0x87d00066cf131ff54B72B134a217D5401E5392b6',
    },

    tokenType: 'OFT',
}
