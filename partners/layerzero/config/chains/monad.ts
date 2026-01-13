import { CustomChainConfig } from '../types'

// Custom endpoint ID for Monad (not in official lz-definitions yet)
export const MONAD_V2_MAINNET = 30390

/**
 * Monad Mainnet configuration
 * Custom chain - LayerZero deployed but not in devtools
 */
export const monad: CustomChainConfig = {
    name: 'monad',
    chainId: 143,
    eid: MONAD_V2_MAINNET,

    rpcUrl: process.env.MONAD_RPC_URL || 'https://rpc-mainnet.monadinfra.com/rpc/tOPaqq0r2zJg6pPOZ5ew6d9CiMFrWamx',
    timeout: 120000,

    explorer: {
        apiUrl: 'https://sourcify-api-monad.blockvision.org',
        browserUrl: 'https://monadexplorer.com',
        apiKey: process.env.MONAD_EXPLORER_API_KEY,
    },

    layerzero: {
        endpointV2: '0x6F475642a6e85809B1c36Fa62763669b1b48DD5B',
        sendUln302: '0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7',
        receiveUln302: '0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043',
        executor: '0x4208D6E27538189bB48E603D6123A94b8Abe0A0b',
        dvns: {
            required: [
                '0xdcdd4628f858b45260c31d6ad076bd2c3d3c2f73', // Horizen
            ],
            optional: [
                '0xacde1f22eeab249d3ca6ba8805c8fee9f52a16e7', // Nethermind
            ],
        },
    },

    wiring: {
        confirmations: 5,
        executorMaxMessageSize: 10000,
        lzReceiveGas: 80000,
    },

    contracts: {
        // pufETH OFT on Monad
        pufETH: '0x37D6382B6889cCeF8d6871A8b60E667115eDDBcF',
    },

    tokenType: 'OFT',
}
