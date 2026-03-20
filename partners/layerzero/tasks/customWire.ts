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

// Check if signer is owner of contract
async function isOwner(contract: any, signerAddress: string): Promise<boolean> {
    try {
        const owner = await contract.owner()
        return owner.toLowerCase() === signerAddress.toLowerCase()
    } catch {
        return false
    }
}

// Generate calldata for a transaction
function encodeTransaction(contract: any, method: string, args: any[]): string {
    return contract.interface.encodeFunctionData(method, args)
}

interface WiringContext {
    hre: HardhatRuntimeEnvironment
    signer: any
    signerAddress: string
    sourceConfig: CustomChainConfig
    destConfig: CustomChainConfig
    token: string
    mode: 'execute' | 'calldata' | 'auto'
    state: WiringState
    dryRun: boolean
    executeEndpointConfig: boolean // When true, skip OFT config and only execute endpoint config
}

// Execute or generate calldata for a step
async function executeStep(
    ctx: WiringContext,
    stepName: keyof WiringState['steps'],
    description: string,
    contract: any,
    method: string,
    args: any[],
    targetAddress: string
): Promise<{ executed: boolean; txHash?: string; calldata?: string }> {
    const step = ctx.state.steps[stepName]

    // Check if already completed (resume functionality)
    if (step?.status === 'completed') {
        console.log(`   [SKIP] ${description} - already completed (tx: ${step.txHash || 'N/A'})`)
        return { executed: true, txHash: step.txHash }
    }

    const calldata = encodeTransaction(contract, method, args)
    const ownerCheck = await isOwner(contract, ctx.signerAddress)

    // Determine execution mode
    const shouldExecute = ctx.mode === 'execute' || (ctx.mode === 'auto' && ownerCheck)

    if (ctx.dryRun) {
        console.log(`   [DRY-RUN] ${description}`)
        console.log(`      To: ${targetAddress}`)
        console.log(`      Data: ${calldata}`)
        console.log(`      Would execute: ${shouldExecute}`)
        return { executed: false, calldata }
    }

    if (shouldExecute) {
        console.log(`   [EXEC] ${description}...`)
        try {
            const tx = await contract[method](...args, { gasLimit: 200_000 })
            console.log(`      Transaction: ${tx.hash}`)
            await tx.wait()
            console.log(`      Confirmed`)

            // Update state
            ctx.state.steps[stepName] = {
                name: description,
                status: 'completed',
                txHash: tx.hash,
                timestamp: Date.now(),
            }
            saveState(ctx.state)

            return { executed: true, txHash: tx.hash }
        } catch (error: any) {
            console.log(`      FAILED: ${error.message}`)
            ctx.state.steps[stepName] = {
                name: description,
                status: 'pending',
                error: error.message,
                timestamp: Date.now(),
            }
            saveState(ctx.state)
            throw error
        }
    } else {
        console.log(`   [CALLDATA] ${description}`)
        console.log(`      Not owner - generating calldata`)
        console.log(`      To: ${targetAddress}`)
        console.log(`      Data: ${calldata}`)

        ctx.state.steps[stepName] = {
            name: description,
            status: 'pending',
            calldata,
            timestamp: Date.now(),
        }
        saveState(ctx.state)

        return { executed: false, calldata }
    }
}

// Execute endpoint config (special case - called on endpoint, not OFT)
async function executeEndpointConfig(
    ctx: WiringContext,
    stepName: keyof WiringState['steps'],
    description: string,
    endpointContract: any,
    oftAddress: string,
    ulnAddress: string,
    configParams: any[],
    chainConfig: CustomChainConfig
): Promise<{ executed: boolean; txHash?: string; calldata?: string }> {
    const step = ctx.state.steps[stepName]

    if (step?.status === 'completed') {
        console.log(`   [SKIP] ${description} - already completed (tx: ${step.txHash || 'N/A'})`)
        return { executed: true, txHash: step.txHash }
    }

    const calldata = endpointContract.interface.encodeFunctionData('setConfig', [oftAddress, ulnAddress, configParams])

    // For endpoint config, check if delegate is set (we might have permission)
    // For now, we'll check if we're the OFT owner as a proxy
    const oftContract = await ctx.hre.ethers.getContractAt('OFT', oftAddress, ctx.signer)
    const ownerCheck = await isOwner(oftContract, ctx.signerAddress)
    const shouldExecute = ctx.mode === 'execute' || (ctx.mode === 'auto' && ownerCheck)

    if (ctx.dryRun) {
        console.log(`   [DRY-RUN] ${description}`)
        console.log(`      To: ${chainConfig.layerzero.endpointV2}`)
        console.log(`      Data: ${calldata}`)
        return { executed: false, calldata }
    }

    if (shouldExecute) {
        console.log(`   [EXEC] ${description}...`)
        try {
            const tx = await endpointContract.setConfig(oftAddress, ulnAddress, configParams, { gasLimit: 290_000 })
            console.log(`      Transaction: ${tx.hash}`)
            await tx.wait()
            console.log(`      Confirmed`)

            ctx.state.steps[stepName] = {
                name: description,
                status: 'completed',
                txHash: tx.hash,
                timestamp: Date.now(),
            }
            saveState(ctx.state)

            return { executed: true, txHash: tx.hash }
        } catch (error: any) {
            console.log(`      FAILED: ${error.message}`)
            ctx.state.steps[stepName] = {
                name: description,
                status: 'pending',
                error: error.message,
                timestamp: Date.now(),
            }
            saveState(ctx.state)
            throw error
        }
    } else {
        console.log(`   [CALLDATA] ${description}`)
        console.log(`      To: ${chainConfig.layerzero.endpointV2}`)
        console.log(`      Data: ${calldata}`)

        ctx.state.steps[stepName] = {
            name: description,
            status: 'pending',
            calldata,
            timestamp: Date.now(),
        }
        saveState(ctx.state)

        return { executed: false, calldata }
    }
}

// Wire source chain (e.g., Ethereum with OFTAdapter)
// Default: Generate calldata for OFT-level calls only (setPeer, setEnforcedOptions) - for Safe multisig
// With --execute-endpoint-config: Execute EndpointV2 config directly (after Safe transactions confirm)
async function wireSourceChain(
    ctx: WiringContext,
    sourceContract: any,
    sourceAddress: string,
    destAddress: string
): Promise<{ txHashes: string[]; calldatas: Array<{ to: string; data: string; description: string }> }> {
    const { hre, sourceConfig, destConfig } = ctx
    const txHashes: string[] = []
    const calldatas: Array<{ to: string; data: string; description: string }> = []

    console.log(`\n  Source Chain Wiring (${sourceConfig.name})`)
    console.log(`  ─────────────────────────────────────`)

    if (ctx.executeEndpointConfig) {
        // --execute-endpoint-config flag: Skip OFT config (assume Safe already executed), execute endpoint config directly
        console.log('   [MODE] Executing EndpointV2 config only (assuming Safe already executed setPeer/setEnforcedOptions)\n')

        const endpointContract = await hre.ethers.getContractAt(
            'ILayerZeroEndpointV2',
            sourceConfig.layerzero.endpointV2,
            ctx.signer
        )

        const ulnConfig = hre.ethers.utils.defaultAbiCoder.encode(
            ['(uint64,uint8,uint8,uint8,address[],address[])'],
            [
                [
                    sourceConfig.wiring.confirmations,
                    sourceConfig.layerzero.dvns.required.length,
                    sourceConfig.layerzero.dvns.optional?.length || 0,
                    0, // optionalDVNThreshold
                    sourceConfig.layerzero.dvns.required,
                    sourceConfig.layerzero.dvns.optional || [],
                ],
            ]
        )

        // Step 3: Set Send Config (on EndpointV2) - execute directly
        const sendConfigParams = [{ eid: destConfig.eid, configType: 2, config: ulnConfig }]

        console.log('   [EXEC] Set send config (DVN)...')
        if (!ctx.dryRun) {
            try {
                console.log('      Estimating gas...')
                const gasEstimate = await endpointContract.estimateGas.setConfig(
                    sourceAddress,
                    sourceConfig.layerzero.sendUln302,
                    sendConfigParams
                )
                console.log(`      Gas estimate: ${gasEstimate.toString()}`)

                console.log('      Sending transaction...')
                const tx = await endpointContract.setConfig(
                    sourceAddress,
                    sourceConfig.layerzero.sendUln302,
                    sendConfigParams,
                    { gasLimit: gasEstimate.mul(120).div(100) } // 20% buffer
                )
                console.log(`      Transaction: ${tx.hash}`)
                console.log(`      Explorer: https://etherscan.io/tx/${tx.hash}`)
                console.log('      Waiting for confirmation...')
                const receipt = await tx.wait(1)
                console.log(`      Confirmed in block ${receipt.blockNumber}`)
                txHashes.push(tx.hash)
            } catch (error: any) {
                console.log(`      FAILED: ${error.reason || error.message}`)
                if (error.code === 'TIMEOUT') {
                    console.log('      Transaction may still be pending. Check explorer.')
                }
                throw error
            }
        } else {
            console.log('      [DRY-RUN] Would execute setSendConfig')
        }

        // Step 4: Set Receive Config (on EndpointV2) - execute directly
        const receiveConfigParams = [{ eid: destConfig.eid, configType: 2, config: ulnConfig }]

        console.log('   [EXEC] Set receive config (DVN)...')
        if (!ctx.dryRun) {
            try {
                console.log('      Estimating gas...')
                const gasEstimate = await endpointContract.estimateGas.setConfig(
                    sourceAddress,
                    sourceConfig.layerzero.receiveUln302,
                    receiveConfigParams
                )
                console.log(`      Gas estimate: ${gasEstimate.toString()}`)

                console.log('      Sending transaction...')
                const tx = await endpointContract.setConfig(
                    sourceAddress,
                    sourceConfig.layerzero.receiveUln302,
                    receiveConfigParams,
                    { gasLimit: gasEstimate.mul(120).div(100) } // 20% buffer
                )
                console.log(`      Transaction: ${tx.hash}`)
                console.log(`      Explorer: https://etherscan.io/tx/${tx.hash}`)
                console.log('      Waiting for confirmation...')
                const receipt = await tx.wait(1)
                console.log(`      Confirmed in block ${receipt.blockNumber}`)
                txHashes.push(tx.hash)
            } catch (error: any) {
                console.log(`      FAILED: ${error.reason || error.message}`)
                if (error.code === 'TIMEOUT') {
                    console.log('      Transaction may still be pending. Check explorer.')
                }
                throw error
            }
        } else {
            console.log('      [DRY-RUN] Would execute setReceiveConfig')
        }
    } else {
        // Default: Generate calldata for OFT-level calls only (for Safe multisig)
        console.log('   [MODE] Generating calldata for Safe multisig (OFT-level calls only)\n')

        // Step 1: Set Peer
        const peerBytes32 = addressToBytes32(destAddress)
        const peerCalldata = encodeTransaction(sourceContract, 'setPeer', [destConfig.eid, peerBytes32])
        console.log(`   [CALLDATA] Set peer to ${destConfig.name} (EID: ${destConfig.eid})`)
        console.log(`      To: ${sourceAddress}`)
        console.log(`      Data: ${peerCalldata}`)
        calldatas.push({ to: sourceAddress, data: peerCalldata, description: 'setPeer' })

        // Step 2: Set Enforced Options
        const lzReceiveGas = destConfig.wiring.lzReceiveGas || 80000

        // msgType 1 (SEND): only needs lzReceive gas
        const optionsSend = Options.newOptions()
            .addExecutorLzReceiveOption(lzReceiveGas, 0)
            .toHex()

        // msgType 2 (SEND_AND_CALL): needs lzReceive + lzCompose gas
        const optionsSendAndCall = Options.newOptions()
            .addExecutorLzReceiveOption(lzReceiveGas, 0)
            .addExecutorComposeOption(0, lzReceiveGas, 0)
            .toHex()

        const enforcedOptions = [
            { eid: destConfig.eid, msgType: 1, options: optionsSend }, // SEND
            { eid: destConfig.eid, msgType: 2, options: optionsSendAndCall }, // SEND_AND_CALL
        ]
        const optionsCalldata = encodeTransaction(sourceContract, 'setEnforcedOptions', [enforcedOptions])
        console.log(`   [CALLDATA] Set enforced options`)
        console.log(`      To: ${sourceAddress}`)
        console.log(`      Data: ${optionsCalldata}`)
        calldatas.push({ to: sourceAddress, data: optionsCalldata, description: 'setEnforcedOptions' })

        console.log('\n   [INFO] After Safe executes these transactions, run with --execute-endpoint-config to complete wiring')
    }

    return { txHashes, calldatas }
}

// Wire destination chain (e.g., Monad with OFT)
async function wireDestChain(
    ctx: WiringContext,
    destContract: any,
    destAddress: string,
    sourceAddress: string
): Promise<{ txHashes: string[]; calldatas: Array<{ to: string; data: string; description: string }> }> {
    const { hre, sourceConfig, destConfig } = ctx
    const txHashes: string[] = []
    const calldatas: Array<{ to: string; data: string; description: string }> = []

    console.log(`\n  Destination Chain Wiring (${destConfig.name})`)
    console.log(`  ─────────────────────────────────────────`)

    // Step 1: Set Peer
    const peerBytes32 = addressToBytes32(sourceAddress)
    const peerResult = await executeStep(
        ctx,
        'dest_setPeer',
        `Set peer to ${sourceConfig.name} (EID: ${sourceConfig.eid})`,
        destContract,
        'setPeer',
        [sourceConfig.eid, peerBytes32],
        destAddress
    )
    if (peerResult.txHash) txHashes.push(peerResult.txHash)
    if (peerResult.calldata) calldatas.push({ to: destAddress, data: peerResult.calldata, description: 'setPeer' })

    // Step 2: Set Enforced Options
    const lzReceiveGas = sourceConfig.wiring.lzReceiveGas || 80000

    // msgType 1 (SEND): only needs lzReceive gas
    const optionsSend = Options.newOptions()
        .addExecutorLzReceiveOption(lzReceiveGas, 0)
        .toHex()

    // msgType 2 (SEND_AND_CALL): needs lzReceive + lzCompose gas
    const optionsSendAndCall = Options.newOptions()
        .addExecutorLzReceiveOption(lzReceiveGas, 0)
        .addExecutorComposeOption(0, lzReceiveGas, 0)
        .toHex()

    const enforcedOptions = [
        { eid: sourceConfig.eid, msgType: 1, options: optionsSend }, // SEND
        { eid: sourceConfig.eid, msgType: 2, options: optionsSendAndCall }, // SEND_AND_CALL
    ]
    const optionsResult = await executeStep(
        ctx,
        'dest_setEnforcedOptions',
        'Set enforced options',
        destContract,
        'setEnforcedOptions',
        [enforcedOptions],
        destAddress
    )
    if (optionsResult.txHash) txHashes.push(optionsResult.txHash)
    if (optionsResult.calldata)
        calldatas.push({ to: destAddress, data: optionsResult.calldata, description: 'setEnforcedOptions' })

    // Step 3 & 4: Set Send/Receive Config (on EndpointV2)
    const endpointContract = await hre.ethers.getContractAt(
        'ILayerZeroEndpointV2',
        destConfig.layerzero.endpointV2,
        ctx.signer
    )

    const ulnConfig = hre.ethers.utils.defaultAbiCoder.encode(
        ['(uint64,uint8,uint8,uint8,address[],address[])'],
        [
            [
                destConfig.wiring.confirmations,
                destConfig.layerzero.dvns.required.length,
                destConfig.layerzero.dvns.optional?.length || 0,
                0,
                destConfig.layerzero.dvns.required,
                destConfig.layerzero.dvns.optional || [],
            ],
        ]
    )
    const sendConfigParams = [{ eid: sourceConfig.eid, configType: 2, config: ulnConfig }]

    const sendConfigResult = await executeEndpointConfig(
        ctx,
        'dest_setSendConfig',
        'Set send config (DVN)',
        endpointContract,
        destAddress,
        destConfig.layerzero.sendUln302,
        sendConfigParams,
        destConfig
    )
    if (sendConfigResult.txHash) txHashes.push(sendConfigResult.txHash)
    if (sendConfigResult.calldata)
        calldatas.push({
            to: destConfig.layerzero.endpointV2,
            data: sendConfigResult.calldata,
            description: 'setSendConfig',
        })

    // Step 4: Set Receive Config (on EndpointV2)
    const receiveConfigParams = [{ eid: sourceConfig.eid, configType: 2, config: ulnConfig }]

    const receiveConfigResult = await executeEndpointConfig(
        ctx,
        'dest_setReceiveConfig',
        'Set receive config (DVN)',
        endpointContract,
        destAddress,
        destConfig.layerzero.receiveUln302,
        receiveConfigParams,
        destConfig
    )
    if (receiveConfigResult.txHash) txHashes.push(receiveConfigResult.txHash)
    if (receiveConfigResult.calldata)
        calldatas.push({
            to: destConfig.layerzero.endpointV2,
            data: receiveConfigResult.calldata,
            description: 'setReceiveConfig',
        })

    return { txHashes, calldatas }
}

// Main task
task('custom:wire', 'Deploy and wire OFT contracts for custom chains')
    .addParam('token', 'Token to wire (pufETH or PUFFER)')
    .addParam('dest', 'Destination chain name (e.g., monad, megaeth)')
    .addOptionalParam('source', 'Source chain name (default: ethereum-mainnet)', 'ethereum-mainnet')
    .addOptionalParam('mode', 'Execution mode: auto, execute, or calldata (default: auto)', 'auto')
    .addFlag('restart', 'Ignore saved state and start fresh')
    .addFlag('dryRun', 'Show what would be done without executing')
    .addFlag('sourceOnly', 'Only wire source chain')
    .addFlag('destOnly', 'Only wire destination chain')
    .addFlag('executeEndpointConfig', 'Execute EndpointV2 config only (after Safe executes setPeer/setEnforcedOptions)')
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        const { token, source, dest, mode, restart, dryRun, sourceOnly, destOnly, executeEndpointConfig } = taskArgs

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
        console.log(`  Mode: ${mode}`)
        console.log(`  Dry Run: ${dryRun}`)
        console.log(`  Execute Endpoint Config Only: ${executeEndpointConfig}`)
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

            // Switch to source network
            const sourceProvider = new hre.ethers.providers.JsonRpcProvider(sourceConfig.rpcUrl)
            const sourceSigner = new hre.ethers.Wallet(process.env.PRIVATE_KEY!, sourceProvider)

            const sourceContract = await hre.ethers.getContractAt('OFTAdapter', sourceAddress, sourceSigner)

            const sourceCtx: WiringContext = {
                hre,
                signer: sourceSigner,
                signerAddress: sourceSigner.address,
                sourceConfig,
                destConfig,
                token,
                mode: mode as 'auto' | 'execute' | 'calldata',
                state,
                dryRun,
                executeEndpointConfig,
            }

            const sourceResult = await wireSourceChain(sourceCtx, sourceContract, sourceAddress, destAddress)
            outputCalldatas.source = sourceResult.calldatas
        }

        // Wire destination chain
        if (!sourceOnly) {
            console.log(`\n  Connecting to ${dest}...`)

            // Switch to dest network
            const destProvider = new hre.ethers.providers.JsonRpcProvider(destConfig.rpcUrl)
            const destSigner = new hre.ethers.Wallet(process.env.PRIVATE_KEY!, destProvider)

            const destContract = await hre.ethers.getContractAt('OFT', destAddress, destSigner)

            const destCtx: WiringContext = {
                hre,
                signer: destSigner,
                signerAddress: destSigner.address,
                sourceConfig,
                destConfig,
                token,
                mode: mode as 'auto' | 'execute' | 'calldata',
                state,
                dryRun,
                executeEndpointConfig: false, // Dest chain always does all steps (we're the owner)
            }

            const destResult = await wireDestChain(destCtx, destContract, destAddress, sourceAddress)
            outputCalldatas.dest = destResult.calldatas
        }

        // Output Safe batch JSONs if there are calldatas
        if (outputCalldatas.source.length > 0 || outputCalldatas.dest.length > 0) {
            if (!fs.existsSync(STATE_DIR)) {
                fs.mkdirSync(STATE_DIR, { recursive: true })
            }
        }

        if (outputCalldatas.source.length > 0) {
            const safeBatch = createSafeBatch(
                sourceConfig.chainId,
                outputCalldatas.source,
                `Wire ${token} on ${source} to ${dest}`
            )
            const outputPath = path.join(STATE_DIR, `safe-batch-${source}-${token}.json`)
            fs.writeFileSync(outputPath, JSON.stringify(safeBatch, null, 2))
            console.log(`\n  Safe batch saved: ${outputPath}`)
        }

        if (outputCalldatas.dest.length > 0) {
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
