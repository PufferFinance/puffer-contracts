import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Options } from '@layerzerolabs/lz-v2-utilities'

/**
 * Manual wiring script for pufETH bridge between Ethereum and Monad
 * Use this when automated wiring fails due to unsupported endpoint IDs
 */

// Configuration
const ETHEREUM_EID = 30101
const MONAD_EID = 30390

const ETHEREUM_CONTRACT = '0xa4931a9F9Aaf79057334371D6f62164743f97b18' // pufETHAdapter
const MONAD_CONTRACT = '0x37D6382B6889cCeF8d6871A8b60E667115eDDBcF' // pufETH

// Monad LayerZero Infrastructure
const MONAD_LZ = {
    endpointV2: '0x6F475642a6e85809B1c36Fa62763669b1b48DD5B',
    sendUln302: '0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7',
    receiveUln302: '0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043',
    executor: '0x4208D6E27538189bB48E603D6123A94b8Abe0A0b',
    dvns: {
        horizen: '0xdcdd4628f858b45260c31d6ad076bd2c3d3c2f73',
        nethermind: '0xacde1f22eeab249d3ca6ba8805c8fee9f52a16e7',
    },
}

// Ethereum LayerZero Infrastructure
const ETHEREUM_LZ = {
    endpointV2: '0x1a44076050125825900e736c501f859c50fE728c',
    sendUln302: '0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1',
    receiveUln302: '0xc02Ab410f0734EFa3F14628780e6e695156024C2',
    executor: '0x173272739Bd7Aa6e4e214714048a9fE699453059',
    dvns: {
        horizen: '0x380275805876ff19055ea900cdb2b46a94ecf20d',
        nethermind: '0xa59ba433ac34d2927232918ef5b2eaafcf130ba5',
    },
}

// Helper to convert address to bytes32
function addressToBytes32(address: string): string {
    return '0x' + address.slice(2).padStart(64, '0')
}

task('wire:manual', 'Manually wire pufETH contracts between Ethereum and Monad')
    .addParam('net', 'Network to execute on (ethereum-mainnet or monad)')
    .addParam('step', 'Step to execute: peer, enforced-options, send-config, receive-config, or all')
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        const { net, step } = taskArgs
        const { ethers } = hre

        console.log(`\n🔧 Executing step: ${step} on network: ${net}\n`)

        // Get signer
        const [signer] = await ethers.getSigners()
        console.log(`Signer address: ${signer.address}`)

        if (net === 'ethereum-mainnet') {
            await wireEthereum(hre, step, signer)
        } else if (net === 'monad') {
            await wireMonad(hre, step, signer)
        } else {
            throw new Error(`Unknown network: ${net}`)
        }
    })

async function wireEthereum(hre: HardhatRuntimeEnvironment, step: string, signer: any) {
    const { ethers } = hre
    const contract = await ethers.getContractAt('OFTAdapter', ETHEREUM_CONTRACT, signer)

    if (step === 'peer' || step === 'all') {
        console.log('📍 Setting peer on Ethereum...')
        const peerBytes32 = addressToBytes32(MONAD_CONTRACT)
        console.log(`   Peer address (Monad): ${MONAD_CONTRACT}`)
        console.log(`   Peer bytes32: ${peerBytes32}`)
        console.log(`   Monad EID: ${MONAD_EID}`)

        const tx = await contract.setPeer(MONAD_EID, peerBytes32)
        console.log(`   Transaction: ${tx.hash}`)
        await tx.wait()
        console.log('   ✅ Peer set successfully\n')
    }

    if (step === 'enforced-options' || step === 'all') {
        console.log('⚙️  Setting enforced options on Ethereum...')

        // Create enforced options for lzReceive
        const options = Options.newOptions().addExecutorLzReceiveOption(80000, 0).toHex()

        const enforcedOptions = [
            {
                eid: MONAD_EID,
                msgType: 1, // SEND
                options: options,
            },
            {
                eid: MONAD_EID,
                msgType: 2, // SEND_AND_CALL
                options: options,
            },
        ]

        const tx = await contract.setEnforcedOptions(enforcedOptions)
        console.log(`   Transaction: ${tx.hash}`)
        await tx.wait()
        console.log('   ✅ Enforced options set successfully\n')
    }

    if (step === 'send-config' || step === 'all') {
        console.log('📤 Setting send config on Ethereum...')

        // Executor Config: SetConfigParam
        const executorConfig = ethers.utils.defaultAbiCoder.encode(['uint32', 'address'], [10000, ETHEREUM_LZ.executor])

        const setConfigParam = {
            eid: MONAD_EID,
            configType: 1, // EXECUTOR_CONFIG
            config: executorConfig,
        }

        // Get endpoint contract
        const endpointContract = await ethers.getContractAt('ILayerZeroEndpointV2', ETHEREUM_LZ.endpointV2, signer)

        // Set send library first
        // console.log('   Setting send library...')
        // let tx = await endpointContract.setSendLibrary(ETHEREUM_CONTRACT, MONAD_EID, ETHEREUM_LZ.sendUln302)
        // console.log(`   Transaction: ${tx.hash}`)
        // await tx.wait()
        // console.log('   ✅ Send library set\n')

        // Prepare DVN config (encoded as a struct/tuple)
        const ulnConfig = ethers.utils.defaultAbiCoder.encode(
            ['(uint64,uint8,uint8,uint8,address[],address[])'], // Single tuple parameter
            [
                [
                    5, // confirmations
                    1, // requiredDVNCount
                    0, // optionalDVNCount
                    0, // optionalDVNThreshold
                    [ETHEREUM_LZ.dvns.horizen], // requiredDVNs
                    [], // optionalDVNs
                ],
            ]
        )

        const dvnConfigParam = {
            eid: MONAD_EID,
            configType: 2, // ULN_CONFIG
            config: ulnConfig,
        }

        // Combine executor config and DVN config into one transaction
        console.log('   Setting executor and DVN config (combined)...')
        let tx = await endpointContract.setConfig(ETHEREUM_CONTRACT, ETHEREUM_LZ.sendUln302, [
            // setConfigParam, // Executor config (configType 1)
            dvnConfigParam, // DVN config (configType 2)
        ])
        console.log(`   Transaction: ${tx.hash}`)
        await tx.wait()
        console.log('   ✅ Executor and DVN config set successfully\n')
    }

    if (step === 'receive-config' || step === 'all') {
        console.log('📥 Setting receive config on Ethereum...')

        const endpointContract = await ethers.getContractAt('ILayerZeroEndpointV2', ETHEREUM_LZ.endpointV2, signer)

        // Set receive library
        // console.log('   Setting receive library...')
        // let tx = await endpointContract.setReceiveLibrary(ETHEREUM_CONTRACT, MONAD_EID, ETHEREUM_LZ.receiveUln302, 0)
        // console.log(`   Transaction: ${tx.hash}`)
        // await tx.wait()
        // console.log('   ✅ Receive library set\n')

        // Set receive ULN config (called on endpoint, not OFT)
        console.log('   Setting receive ULN config...')
        const ulnConfig = ethers.utils.defaultAbiCoder.encode(
            ['(uint64,uint8,uint8,uint8,address[],address[])'], // Single tuple parameter
            [
                [
                    5, // confirmations
                    1, // requiredDVNCount
                    0, // optionalDVNCount
                    0, // optionalDVNThreshold
                    [ETHEREUM_LZ.dvns.horizen], // requiredDVNs
                    [], // optionalDVNs
                ],
            ]
        )

        const receiveConfigParam = {
            eid: MONAD_EID,
            configType: 2,
            config: ulnConfig,
        }

        let tx = await endpointContract.setConfig(ETHEREUM_CONTRACT, ETHEREUM_LZ.receiveUln302, [receiveConfigParam])
        console.log(`   Transaction: ${tx.hash}`)
        await tx.wait()
        console.log('   ✅ Receive config set successfully\n')
    }

    console.log('✅ Ethereum wiring complete!')
}

async function wireMonad(hre: HardhatRuntimeEnvironment, step: string, signer: any) {
    const { ethers } = hre
    const contract = await ethers.getContractAt('OFT', MONAD_CONTRACT, signer)

    if (step === 'peer' || step === 'all') {
        console.log('📍 Setting peer on Monad...')
        const peerBytes32 = addressToBytes32(ETHEREUM_CONTRACT)
        console.log(`   Peer address (Ethereum): ${ETHEREUM_CONTRACT}`)
        console.log(`   Peer bytes32: ${peerBytes32}`)
        console.log(`   Ethereum EID: ${ETHEREUM_EID}`)

        const tx = await contract.setPeer(ETHEREUM_EID, peerBytes32)
        console.log(`   Transaction: ${tx.hash}`)
        await tx.wait()
        console.log('   ✅ Peer set successfully\n')
    }

    if (step === 'enforced-options' || step === 'all') {
        console.log('⚙️  Setting enforced options on Monad...')

        const options = Options.newOptions().addExecutorLzReceiveOption(80000, 0).toHex()

        const enforcedOptions = [
            {
                eid: ETHEREUM_EID,
                msgType: 1,
                options: options,
            },
            {
                eid: ETHEREUM_EID,
                msgType: 2,
                options: options,
            },
        ]

        const tx = await contract.setEnforcedOptions(enforcedOptions)
        console.log(`   Transaction: ${tx.hash}`)
        await tx.wait()
        console.log('   ✅ Enforced options set successfully\n')
    }

    if (step === 'send-config' || step === 'all') {
        console.log('📤 Setting send config on Monad...')

        const endpointContract = await ethers.getContractAt('ILayerZeroEndpointV2', MONAD_LZ.endpointV2, signer)

        // Set send library
        // console.log('   Setting send library...')
        // let tx = await endpointContract.setSendLibrary(MONAD_CONTRACT, ETHEREUM_EID, MONAD_LZ.sendUln302)
        // console.log(`   Transaction: ${tx.hash}`)
        // await tx.wait()
        // console.log('   ✅ Send library set\n')

        // Prepare executor config
        const executorConfig = ethers.utils.defaultAbiCoder.encode(['uint32', 'address'], [10000, MONAD_LZ.executor])

        const executorConfigParam = {
            eid: ETHEREUM_EID,
            configType: 1, // EXECUTOR_CONFIG
            config: executorConfig,
        }

        // Prepare DVN config (encoded as a struct/tuple)
        const ulnConfig = ethers.utils.defaultAbiCoder.encode(
            ['(uint64,uint8,uint8,uint8,address[],address[])'], // Single tuple parameter
            [
                [
                    5, // confirmations
                    1, // requiredDVNCount
                    0, // optionalDVNCount
                    0, // optionalDVNThreshold
                    [MONAD_LZ.dvns.horizen], // requiredDVNs
                    [], // optionalDVNs
                ],
            ]
        )

        const dvnConfigParam = {
            eid: ETHEREUM_EID,
            configType: 2, // ULN_CONFIG
            config: ulnConfig,
        }

        // Combine executor config and DVN config into one transaction
        console.log('   Setting executor and DVN config (combined)...')
        const tx = await endpointContract.setConfig(MONAD_CONTRACT, MONAD_LZ.sendUln302, [
            executorConfigParam, // Executor config (configType 1)
            // DVN config (configType 2)
        ])
        console.log(`   Transaction: ${tx.hash}`)
        await tx.wait()
        console.log('   ✅ Executor and DVN config set successfully\n')
    }

    if (step === 'receive-config' || step === 'all') {
        console.log('📥 Setting receive config on Monad...')

        const endpointContract = await ethers.getContractAt('ILayerZeroEndpointV2', MONAD_LZ.endpointV2, signer)

        // Set receive library
        // console.log('   Setting receive library...')
        // let tx = await endpointContract.setReceiveLibrary(MONAD_CONTRACT, ETHEREUM_EID, MONAD_LZ.receiveUln302, 0)
        // console.log(`   Transaction: ${tx.hash}`)
        // await tx.wait()
        // console.log('   ✅ Receive library set\n')

        // Set receive ULN config (called on endpoint, not OFT)
        console.log('   Setting receive ULN config...')
        const ulnConfig = ethers.utils.defaultAbiCoder.encode(
            ['(uint64,uint8,uint8,uint8,address[],address[])'], // Single tuple parameter
            [
                [
                    5, // confirmations
                    1, // requiredDVNCount
                    0, // optionalDVNCount
                    0, // optionalDVNThreshold
                    [MONAD_LZ.dvns.horizen], // requiredDVNs
                    [], // optionalDVNs
                ],
            ]
        )

        const receiveConfigParam = {
            eid: ETHEREUM_EID,
            configType: 2, // ULN_CONFIG
            config: ulnConfig,
        }

        let tx = await endpointContract.setConfig(MONAD_CONTRACT, MONAD_LZ.receiveUln302, [receiveConfigParam])
        console.log(`   Transaction: ${tx.hash}`)
        await tx.wait()
        console.log('   ✅ Receive config set successfully\n')
    }

    console.log('✅ Monad wiring complete!')
}

task('wire:check', 'Check wiring status')
    .addParam('net', 'Network to check (ethereum-mainnet or monad)')
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        const { net } = taskArgs
        const { ethers } = hre

        console.log(`\n🔍 Checking wiring status on ${net}\n`)

        const [signer] = await ethers.getSigners()

        if (net === 'ethereum-mainnet') {
            const contract = await ethers.getContractAt('OFTAdapter', ETHEREUM_CONTRACT, signer)
            const peer = await contract.peers(MONAD_EID)
            console.log(`Peer on Ethereum for Monad (EID ${MONAD_EID}): ${peer}`)
            console.log(`Expected: ${addressToBytes32(MONAD_CONTRACT)}`)
            console.log(`Match: ${peer.toLowerCase() === addressToBytes32(MONAD_CONTRACT).toLowerCase()}`)
        } else if (net === 'monad') {
            const contract = await ethers.getContractAt('OFT', MONAD_CONTRACT, signer)
            const peer = await contract.peers(ETHEREUM_EID)
            console.log(`Peer on Monad for Ethereum (EID ${ETHEREUM_EID}): ${peer}`)
            console.log(`Expected: ${addressToBytes32(ETHEREUM_CONTRACT)}`)
            console.log(`Match: ${peer.toLowerCase() === addressToBytes32(ETHEREUM_CONTRACT).toLowerCase()}`)
        }
    })
