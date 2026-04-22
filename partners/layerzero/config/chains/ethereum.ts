import { EndpointId } from '@layerzerolabs/lz-definitions'
import { CustomChainConfig } from '../types'

/**
 * Ethereum Mainnet configuration
 * This is typically the source chain where OFTAdapter wraps existing tokens
 */
export const ethereum: CustomChainConfig = {
    name: 'ethereum-mainnet',
    chainId: 1,
    eid: EndpointId.ETHEREUM_V2_MAINNET, // 30101

    rpcUrl: process.env.ETHEREUM_RPC_URL || 'https://eth.llamarpc.com',
    timeout: 120000,

    explorer: {
        apiUrl: 'https://api.etherscan.io/api',
        browserUrl: 'https://etherscan.io',
        apiKey: process.env.ETHERSCAN_API_KEY,
    },

    layerzero: {
        endpointV2: '0x1a44076050125825900e736c501f859c50fE728c',
        sendUln302: '0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1',
        receiveUln302: '0xc02Ab410f0734EFa3F14628780e6e695156024C2',
        executor: '0x173272739Bd7Aa6e4e214714048a9fE699453059',
        dvns: {
            required: [
                '0x380275805876ff19055ea900cdb2b46a94ecf20d', // Horizen
                '0xa59ba433ac34d2927232918ef5b2eaafcf130ba5', // Nethermind
                '0xa4fe5a5b9a846458a70cd0748228aed3bf65c2cd', // Canary
                '0x06559ee34d85a88317bf0bfe307444116c631b67', // P2P
            ],
            optional: [],
        },
    },

    wiring: {
        confirmations: 5, // Ethereum needs more confirmations
        executorMaxMessageSize: 10000,
        lzReceiveGas: 80000,
    },

    contracts: {
        // pufETH OFTAdapter on Ethereum (wraps native pufETH)
        pufETHAdapter: '0xa4931a9F9Aaf79057334371D6f62164743f97b18',
        // PUFFER OFTAdapter would go here if deployed
        PUFFERAdapter: '0x3Ea9bb9fcDCC1C37cB09175aecdb488A97EDd83F',
    },

    tokenType: 'OFTAdapter',
}
