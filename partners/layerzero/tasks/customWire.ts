import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Options } from '@layerzerolabs/lz-v2-utilities'
import * as fs from 'fs'
import * as path from 'path'
import { CustomChainConfig, WiringState, SafeBatch, getChainConfig, listChains } from '../config'

const STATE_DIR = path.join(__dirname, '../.wiring-state')

// Helper to convert address to bytes32
function addressToBytes32(address: string): string {
    return '0x' + address.slice(2).padStart(64, '0')
}

// Load wiring state for resume functionality
function loadState(token: string, source: string, dest: string): WiringState | null {
    const stateFile = path.join(STATE_DIR, `${token}-${source}-${dest}.json`)
    if (fs.existsSync(stateFile)) {
        return JSON.parse(fs.readFileSync(stateFile, 'utf-8'))
    }
    return null
}

// Save wiring state
function saveState(state: WiringState): void {
    if (!fs.existsSync(STATE_DIR)) {
        fs.mkdirSync(STATE_DIR, { recursive: true })
    }
    const stateFile = path.join(STATE_DIR, `${state.token}-${state.sourceChain}-${state.destChain}.json`)
    state.updatedAt = Date.now()
    fs.writeFileSync(stateFile, JSON.stringify(state, null, 2))
}

// Initialize fresh state
function initState(token: string, source: string, dest: string): WiringState {
    return {
        token,
        sourceChain: source,
        destChain: dest,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        steps: {},
    }
}

// Create Safe batch JSON format
function createSafeBatch(
    chainId: number,
    transactions: Array<{ to: string; data: string; description: string }>,
    description: string
): SafeBatch {
    return {
        version: '1.0',
        chainId: chainId.toString(),
        createdAt: Date.now(),
        meta: {
            name: 'LayerZero Custom Wiring',
            description,
        },
        transactions: transactions.map((tx) => ({
            to: tx.to,
            value: '0',
            data: tx.data,
            operation: 0,
        })),
    }
}

// Generate calldata for a transaction
function encodeTransaction(contract: any, method: string, args: any[]): string {
    return contract.interface.encodeFunctionData(method, args)
}

// Simulate a call with an impersonated sender via eth_call (no on-chain effect).
// Used by --dry-run to validate that the calldata would succeed when executed by the multisig.
async function simulateCall(
    provider: any,
    to: string,
    data: string,
    from: string,
    description: string
): Promise<void> {
    try {
        await provider.call({ to, data, from })
        console.log(`      [SIMULATE] ${description}: OK (from ${from})`)
    } catch (error: any) {
        const reason =
            error.reason ||
            error.error?.reason ||
            error.error?.data?.message ||
            error.error?.message ||
            error.message ||
            'unknown'
        console.log(`      [SIMULATE] ${description}: REVERT — ${reason}`)
        if (error.data && typeof error.data === 'string') {
            console.log(`         revert data: ${error.data}`)
        }
    }
}

interface WiringContext {
    hre: HardhatRuntimeEnvironment
    provider: any
    sourceConfig: CustomChainConfig
    destConfig: CustomChainConfig
    token: string
    state: WiringState
    dryRun: boolean
}

// Generate calldata for a step targeting an OFT/OFTAdapter method
function generateStepCalldata(
    ctx: WiringContext,
    stepName: keyof WiringState['steps'],
    description: string,
    contract: any,
    method: string,
    args: any[],
    targetAddress: string
): string {
    const calldata = encodeTransaction(contract, method, args)

    const prefix = ctx.dryRun ? '[DRY-RUN]' : '[CALLDATA]'
    console.log(`   ${prefix} ${description}`)
    console.log(`      To: ${targetAddress}`)
    console.log(`      Data: ${calldata}`)

    if (!ctx.dryRun) {
        ctx.state.steps[stepName] = {
            name: description,
            status: 'pending',
            calldata,
            timestamp: Date.now(),
        }
        saveState(ctx.state)
    }

    return calldata
}

// Generate calldata for endpoint config (called on EndpointV2, not the OFT)
function generateEndpointConfigCalldata(
    ctx: WiringContext,
    stepName: keyof WiringState['steps'],
    description: string,
    endpointContract: any,
    oftAddress: string,
    ulnAddress: string,
    configParams: any[],
    chainConfig: CustomChainConfig
): string {
    const calldata = endpointContract.interface.encodeFunctionData('setConfig', [oftAddress, ulnAddress, configParams])

    const prefix = ctx.dryRun ? '[DRY-RUN]' : '[CALLDATA]'
    console.log(`   ${prefix} ${description}`)
    console.log(`      To: ${chainConfig.layerzero.endpointV2}`)
    console.log(`      Data: ${calldata}`)

    if (!ctx.dryRun) {
        ctx.state.steps[stepName] = {
            name: description,
            status: 'pending',
            calldata,
            timestamp: Date.now(),
        }
        saveState(ctx.state)
    }

    return calldata
}

// Build the encoded ULN config for a chain/peer pair
function buildUlnConfig(hre: HardhatRuntimeEnvironment, chainConfig: CustomChainConfig): string {
    return hre.ethers.utils.defaultAbiCoder.encode(
        ['(uint64,uint8,uint8,uint8,address[],address[])'],
        [
            [
                chainConfig.wiring.confirmations,
                chainConfig.layerzero.dvns.required.length,
                chainConfig.layerzero.dvns.optional?.length || 0,
                chainConfig.layerzero.dvns.threshold || 0,
                chainConfig.layerzero.dvns.required,
                chainConfig.layerzero.dvns.optional || [],
            ],
        ]
    )
}

// Build enforced options for SEND (msgType 1) and SEND_AND_CALL (msgType 2)
function buildEnforcedOptions(peerEid: number, lzReceiveGas: number) {
    const optionsSend = Options.newOptions().addExecutorLzReceiveOption(lzReceiveGas, 0).toHex()
    const optionsSendAndCall = Options.newOptions()
        .addExecutorLzReceiveOption(lzReceiveGas, 0)
        .addExecutorComposeOption(0, lzReceiveGas, 0)
        .toHex()
    return [
        { eid: peerEid, msgType: 1, options: optionsSend },
        { eid: peerEid, msgType: 2, options: optionsSendAndCall },
    ]
}

// Wire a chain by generating calldata for all 4 transactions (to be executed by the multisig owner).
// Works symmetrically for source (OFTAdapter) and destination (OFT) — caller picks which config is
// local vs peer and passes the matching contract type.
async function wireChain(
    ctx: WiringContext,
    localContract: any,
    localAddress: string,
    peerAddress: string,
    localConfig: CustomChainConfig,
    peerConfig: CustomChainConfig,
    stepPrefix: 'source' | 'dest',
    label: string
): Promise<Array<{ to: string; data: string; description: string }>> {
    const { hre, provider } = ctx
    const calldatas: Array<{ to: string; data: string; description: string }> = []

    console.log(`\n  ${label} Chain Wiring (${localConfig.name})`)
    console.log(`  ─────────────────────────────────────`)
    console.log('   [MODE] Generating calldata for Safe multisig\n')

    const endpointArtifact = await hre.artifacts.readArtifact('ILayerZeroEndpointV2')
    const endpointContract = new hre.ethers.Contract(
        localConfig.layerzero.endpointV2,
        endpointArtifact.abi,
        provider
    )

    // For --dry-run, resolve the impersonated senders once per chain:
    // - owner()        → for setPeer / setEnforcedOptions on the OFT/OFTAdapter
    // - delegates(oft) → for setConfig on EndpointV2
    let ownerAddress: string | undefined
    let delegateAddress: string | undefined
    if (ctx.dryRun) {
        const endpointWithGetter = new hre.ethers.Contract(
            localConfig.layerzero.endpointV2,
            ['function delegates(address) view returns (address)'],
            provider
        )
        try {
            ownerAddress = await localContract.owner()
            console.log(`   [INFO] OFT owner: ${ownerAddress}`)
        } catch (e: any) {
            console.log(`   [WARN] Could not fetch owner(): ${e.message}`)
        }
        try {
            delegateAddress = await endpointWithGetter.delegates(localAddress)
            console.log(`   [INFO] Endpoint delegate: ${delegateAddress}`)
            if (delegateAddress === hre.ethers.constants.AddressZero) {
                console.log(`   [WARN] Delegate is unset — setConfig will revert until setDelegate is called`)
                delegateAddress = undefined
            }
        } catch (e: any) {
            console.log(`   [WARN] Could not fetch delegates(): ${e.message}`)
        }
        console.log('')
    }

    // Step 1: Set Peer
    const peerBytes32 = addressToBytes32(peerAddress)
    const peerCalldata = generateStepCalldata(
        ctx,
        `${stepPrefix}_setPeer` as keyof WiringState['steps'],
        `Set peer to ${peerConfig.name} (EID: ${peerConfig.eid})`,
        localContract,
        'setPeer',
        [peerConfig.eid, peerBytes32],
        localAddress
    )
    calldatas.push({ to: localAddress, data: peerCalldata, description: 'setPeer' })
    if (ctx.dryRun && ownerAddress) {
        await simulateCall(provider, localAddress, peerCalldata, ownerAddress, 'setPeer')
    }

    // Step 2: Set Enforced Options
    const lzReceiveGas = peerConfig.wiring.lzReceiveGas || 80000
    const enforcedOptions = buildEnforcedOptions(peerConfig.eid, lzReceiveGas)
    const optionsCalldata = generateStepCalldata(
        ctx,
        `${stepPrefix}_setEnforcedOptions` as keyof WiringState['steps'],
        'Set enforced options',
        localContract,
        'setEnforcedOptions',
        [enforcedOptions],
        localAddress
    )
    calldatas.push({ to: localAddress, data: optionsCalldata, description: 'setEnforcedOptions' })
    if (ctx.dryRun && ownerAddress) {
        await simulateCall(provider, localAddress, optionsCalldata, ownerAddress, 'setEnforcedOptions')
    }

    // Step 3 & 4: Set Send/Receive Config (on EndpointV2)
    const ulnConfig = buildUlnConfig(hre, localConfig)

    const sendConfigParams = [{ eid: peerConfig.eid, configType: 2, config: ulnConfig }]
    const sendConfigCalldata = generateEndpointConfigCalldata(
        ctx,
        `${stepPrefix}_setSendConfig` as keyof WiringState['steps'],
        'Set send config (DVN)',
        endpointContract,
        localAddress,
        localConfig.layerzero.sendUln302,
        sendConfigParams,
        localConfig
    )
    calldatas.push({
        to: localConfig.layerzero.endpointV2,
        data: sendConfigCalldata,
        description: 'setSendConfig',
    })
    if (ctx.dryRun && delegateAddress) {
        await simulateCall(
            provider,
            localConfig.layerzero.endpointV2,
            sendConfigCalldata,
            delegateAddress,
            'setSendConfig'
        )
    }

    const receiveConfigParams = [{ eid: peerConfig.eid, configType: 2, config: ulnConfig }]
    const receiveConfigCalldata = generateEndpointConfigCalldata(
        ctx,
        `${stepPrefix}_setReceiveConfig` as keyof WiringState['steps'],
        'Set receive config (DVN)',
        endpointContract,
        localAddress,
        localConfig.layerzero.receiveUln302,
        receiveConfigParams,
        localConfig
    )
    calldatas.push({
        to: localConfig.layerzero.endpointV2,
        data: receiveConfigCalldata,
        description: 'setReceiveConfig',
    })
    if (ctx.dryRun && delegateAddress) {
        await simulateCall(
            provider,
            localConfig.layerzero.endpointV2,
            receiveConfigCalldata,
            delegateAddress,
            'setReceiveConfig'
        )
    }

    return calldatas
}

// Main task
task('custom:wire', 'Generate Safe multisig calldata to wire OFT contracts for custom chains')
    .addParam('token', 'Token to wire (pufETH or PUFFER)')
    .addParam('dest', 'Destination chain name (e.g., monad, megaeth)')
    .addOptionalParam('source', 'Source chain name (default: ethereum-mainnet)', 'ethereum-mainnet')
    .addFlag('restart', 'Ignore saved state and start fresh')
    .addFlag('dryRun', 'Show what would be done without writing state or Safe batch files')
    .addFlag('sourceOnly', 'Only wire source chain')
    .addFlag('destOnly', 'Only wire destination chain')
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        const { token, source, dest, restart, dryRun, sourceOnly, destOnly } = taskArgs

        console.log('\n╔═══════════════════════════════════════════════════════════╗')
        console.log('║           LayerZero Custom Chain Wiring                   ║')
        console.log('╚═══════════════════════════════════════════════════════════╝\n')

        // Validate inputs
        const sourceConfig = getChainConfig(source)
        const destConfig = getChainConfig(dest)

        if (!sourceConfig) {
            console.error(`Unknown source chain: ${source}`)
            console.log(`Available chains: ${listChains().join(', ')}`)
            return
        }

        if (!destConfig) {
            console.error(`Unknown destination chain: ${dest}`)
            console.log(`Available chains: ${listChains().join(', ')}`)
            return
        }

        // Get contract addresses from config
        const tokenKey = token.toLowerCase() === 'pufeth' ? 'pufETH' : 'PUFFER'
        const adapterKey = `${tokenKey}Adapter`

        const sourceAddress = sourceConfig.contracts?.[adapterKey as keyof typeof sourceConfig.contracts]
        const destAddress = destConfig.contracts?.[tokenKey as keyof typeof destConfig.contracts]

        if (!sourceAddress) {
            console.error(`No ${adapterKey} contract configured for ${source}`)
            console.log(`Please update config/chains/${source}.ts with the contract address`)
            return
        }

        if (!destAddress) {
            console.error(`No ${tokenKey} contract configured for ${dest}`)
            console.log(`Please update config/chains/${dest}.ts with the contract address`)
            return
        }

        console.log(`  Token: ${token}`)
        console.log(`  Source: ${source} (${sourceAddress})`)
        console.log(`  Dest: ${dest} (${destAddress})`)
        console.log(`  Dry Run: ${dryRun}`)
        console.log('')

        // Load or initialize state
        let state: WiringState
        if (restart) {
            console.log('  [RESTART] Starting fresh - ignoring saved state\n')
            state = initState(token, source, dest)
        } else {
            const existingState = loadState(token, source, dest)
            if (existingState) {
                console.log('  [RESUME] Found existing state - resuming from last checkpoint\n')
                state = existingState
            } else {
                state = initState(token, source, dest)
            }
        }

        const outputCalldatas: {
            source: Array<{ to: string; data: string; description: string }>
            dest: Array<{ to: string; data: string; description: string }>
        } = { source: [], dest: [] }

        // Wire source chain
        if (!destOnly) {
            console.log(`\n  Connecting to ${source}...`)

            const sourceProvider = new hre.ethers.providers.JsonRpcProvider(sourceConfig.rpcUrl)
            const sourceArtifact = await hre.artifacts.readArtifact('OFTAdapter')
            const sourceContract = new hre.ethers.Contract(sourceAddress, sourceArtifact.abi, sourceProvider)

            const sourceCtx: WiringContext = {
                hre,
                provider: sourceProvider,
                sourceConfig,
                destConfig,
                token,
                state,
                dryRun,
            }

            outputCalldatas.source = await wireChain(
                sourceCtx,
                sourceContract,
                sourceAddress,
                destAddress,
                sourceConfig,
                destConfig,
                'source',
                'Source'
            )
        }

        // Wire destination chain
        if (!sourceOnly) {
            console.log(`\n  Connecting to ${dest}...`)

            const destProvider = new hre.ethers.providers.JsonRpcProvider(destConfig.rpcUrl)
            const destArtifact = await hre.artifacts.readArtifact('OFT')
            const destContract = new hre.ethers.Contract(destAddress, destArtifact.abi, destProvider)

            const destCtx: WiringContext = {
                hre,
                provider: destProvider,
                sourceConfig,
                destConfig,
                token,
                state,
                dryRun,
            }

            outputCalldatas.dest = await wireChain(
                destCtx,
                destContract,
                destAddress,
                sourceAddress,
                destConfig,
                sourceConfig,
                'dest',
                'Destination'
            )
        }

        // Output Safe batch JSONs if there are calldatas
        if (!dryRun && (outputCalldatas.source.length > 0 || outputCalldatas.dest.length > 0)) {
            if (!fs.existsSync(STATE_DIR)) {
                fs.mkdirSync(STATE_DIR, { recursive: true })
            }
        }

        if (!dryRun && outputCalldatas.source.length > 0) {
            const safeBatch = createSafeBatch(
                sourceConfig.chainId,
                outputCalldatas.source,
                `Wire ${token} on ${source} to ${dest}`
            )
            const outputPath = path.join(STATE_DIR, `safe-batch-${source}-${token}.json`)
            fs.writeFileSync(outputPath, JSON.stringify(safeBatch, null, 2))
            console.log(`\n  Safe batch saved: ${outputPath}`)
        }

        if (!dryRun && outputCalldatas.dest.length > 0) {
            const safeBatch = createSafeBatch(
                destConfig.chainId,
                outputCalldatas.dest,
                `Wire ${token} on ${dest} to ${source}`
            )
            const outputPath = path.join(STATE_DIR, `safe-batch-${dest}-${token}.json`)
            fs.writeFileSync(outputPath, JSON.stringify(safeBatch, null, 2))
            console.log(`  Safe batch saved: ${outputPath}`)
        }

        console.log('\n╔═══════════════════════════════════════════════════════════╗')
        console.log('║                    Wiring Complete                        ║')
        console.log('╚═══════════════════════════════════════════════════════════╝\n')
    })

// Check wiring status
task('custom:check', 'Check wiring status for custom chain deployment')
    .addParam('token', 'Token to check (pufETH or PUFFER)')
    .addParam('dest', 'Destination chain name')
    .addOptionalParam('source', 'Source chain name', 'ethereum-mainnet')
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        const { token, source, dest } = taskArgs

        const sourceConfig = getChainConfig(source)
        const destConfig = getChainConfig(dest)

        if (!sourceConfig || !destConfig) {
            console.error('Invalid chain configuration')
            return
        }

        const tokenKey = token.toLowerCase() === 'pufeth' ? 'pufETH' : 'PUFFER'
        const adapterKey = `${tokenKey}Adapter`

        const sourceAddress = sourceConfig.contracts?.[adapterKey as keyof typeof sourceConfig.contracts]
        const destAddress = destConfig.contracts?.[tokenKey as keyof typeof destConfig.contracts]

        console.log('\n  Checking Wiring Status')
        console.log('  ══════════════════════\n')

        // Check source chain
        console.log(`  Source (${source}):`)
        const sourceProvider = new hre.ethers.providers.JsonRpcProvider(sourceConfig.rpcUrl)
        const sourceContract = new hre.ethers.Contract(
            sourceAddress!,
            ['function peers(uint32) view returns (bytes32)'],
            sourceProvider
        )

        try {
            const peer = await sourceContract.peers(destConfig.eid)
            const expectedPeer = addressToBytes32(destAddress!)
            const peerMatch = peer.toLowerCase() === expectedPeer.toLowerCase()
            console.log(`    Peer configured: ${peerMatch ? 'YES' : 'NO'}`)
            if (!peerMatch) {
                console.log(`      Current: ${peer}`)
                console.log(`      Expected: ${expectedPeer}`)
            }
        } catch (e) {
            console.log(`    Peer check failed: ${e}`)
        }

        // Check dest chain
        console.log(`\n  Destination (${dest}):`)
        const destProvider = new hre.ethers.providers.JsonRpcProvider(destConfig.rpcUrl)
        const destContract = new hre.ethers.Contract(
            destAddress!,
            ['function peers(uint32) view returns (bytes32)'],
            destProvider
        )

        try {
            const peer = await destContract.peers(sourceConfig.eid)
            const expectedPeer = addressToBytes32(sourceAddress!)
            const peerMatch = peer.toLowerCase() === expectedPeer.toLowerCase()
            console.log(`    Peer configured: ${peerMatch ? 'YES' : 'NO'}`)
            if (!peerMatch) {
                console.log(`      Current: ${peer}`)
                console.log(`      Expected: ${expectedPeer}`)
            }
        } catch (e) {
            console.log(`    Peer check failed: ${e}`)
        }

        // Check saved state
        const stateData = loadState(token, source, dest)
        if (stateData) {
            console.log('\n  Saved State:')
            for (const [stepName, step] of Object.entries(stateData.steps)) {
                if (step) {
                    console.log(`    ${stepName}: ${step.status}${step.txHash ? ` (${step.txHash})` : ''}`)
                }
            }
        }

        console.log('')
    })

// List available chains
task('custom:chains', 'List available custom chain configurations').setAction(async () => {
    console.log('\n  Available Chains')
    console.log('  ════════════════\n')

    for (const name of listChains()) {
        const config = getChainConfig(name)
        if (config) {
            console.log(`  ${name}`)
            console.log(`    Chain ID: ${config.chainId}`)
            console.log(`    EID: ${config.eid}`)
            console.log(`    Endpoint: ${config.layerzero.endpointV2}`)
            if (config.contracts?.pufETH) console.log(`    pufETH: ${config.contracts.pufETH}`)
            if (config.contracts?.pufETHAdapter) console.log(`    pufETHAdapter: ${config.contracts.pufETHAdapter}`)
            console.log('')
        }
    }
})
