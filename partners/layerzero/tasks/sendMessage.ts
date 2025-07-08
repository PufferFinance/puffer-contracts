// tasks/sendMessage.ts

import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { Options } from '@layerzerolabs/lz-v2-utilities'

export default task('sendMessage', 'Send a message to the destination chain')
    .addParam('dstNetwork', 'The destination network name (from hardhat.config.ts)')
    .addParam('message', 'The message to send')
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        const { message, dstNetwork } = taskArgs
        const [signer] = await hre.ethers.getSigners()

        // Get destination network's EID
        const dstNetworkConfig = hre.config.networks[dstNetwork]
        const dstEid = dstNetworkConfig.eid

        // Get current network's EID
        const srcNetworkConfig = hre.config.networks[hre.network.name]
        const srcEid = srcNetworkConfig?.eid

        console.log('Sending message:')
        console.log('- From:', signer.address)
        console.log('- Source network:', hre.network.name, srcEid ? `(EID: ${srcEid})` : '')
        console.log('- Destination:', dstNetwork || 'unknown network', `(EID: ${dstEid})`)
        console.log('- Message:', message)

        const myOApp = await hre.deployments.get('MyOApp')
        const contract = await hre.ethers.getContractAt('MyOApp', myOApp.address, signer)

        // Add executor options with gas limit
        const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toBytes()

        // Get quote for the message
        console.log('Getting quote...')
        const quotedFee = await contract.quote(dstEid, message, options, false)
        console.log('Quoted fee:', hre.ethers.utils.formatEther(quotedFee.nativeFee))

        // Send the message
        console.log('Sending message...')
        const tx = await contract.send(dstEid, message, options, { value: quotedFee.nativeFee })

        const receipt = await tx.wait()
        console.log('🎉 Message sent! Transaction hash:', receipt.transactionHash)
        console.log(
            'Check message status on LayerZero Scan: https://testnet.layerzeroscan.com/tx/' + receipt.transactionHash
        )
    })
