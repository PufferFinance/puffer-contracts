import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { OAppEnforcedOption, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { generateConnectionsConfig } from '@layerzerolabs/metadata-tools'

const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    contractName: 'pufETHAdapter',
}

// const bscContract: OmniPointHardhat = {
//     eid: EndpointId.BSC_V2_MAINNET,
//     contractName: 'PUFFER',
// }

// const hyperEVMContract: OmniPointHardhat = {
//     eid: EndpointId.HYPERLIQUID_V2_MAINNET,
//     contractName: 'pufETH',
// }

const tacMainnetContract: OmniPointHardhat = {
    eid: EndpointId.TAC_V2_MAINNET,
    contractName: 'pufETH',
}

const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: 1,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 80000,
        value: 0,
    },
    {
        msgType: 2,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 80000,
        value: 0,
    },
    {
        msgType: 2,
        optionType: ExecutorOptionType.COMPOSE,
        index: 0,
        gas: 80000,
        value: 0,
    },
]

export default async function () {
    const connections = await generateConnectionsConfig([
        [
            ethereumContract,
            tacMainnetContract,
            [['P2P', 'Horizen'], []],
            [15, 15],
            [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ])

    return {
        contracts: [{ contract: ethereumContract }, { contract: tacMainnetContract }],
        connections,
    }
}
