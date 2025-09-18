// Remember to add this script to your hardhat.config.ts via an `import './tasks/send'
// An example of running this script is:
// npx hardhat lz:oft:send --amount 1 --to 0xd8da6bf26964af9d7eed9e03e53415d37aa96045 --to-eid 40245 --network avalanche-testnet

import { task } from 'hardhat/config'
import { getNetworkNameForEid, types } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { addressToBytes32 } from '@layerzerolabs/lz-v2-utilities'
import { Options } from '@layerzerolabs/lz-v2-utilities'
import { BigNumberish, BytesLike } from 'ethers'

interface Args {
    amount: string
    to: string
    toEid: EndpointId
}

interface SendParam {
    dstEid: EndpointId // Destination endpoint ID, represented as a number.
    to: BytesLike // Recipient address, represented as bytes.
    amountLD: BigNumberish // Amount to send in local decimals.
    minAmountLD: BigNumberish // Minimum amount to send in local decimals.
    extraOptions: BytesLike // Additional options supplied by the caller to be used in the LayerZero message.
    composeMsg: BytesLike // The composed message for the send() operation.
    oftCmd: BytesLike // The OFT command to be executed, unused in default OFT implementations.
}

// Send tokens from a contract on one network to another
task('lz:oft:send', 'Sends tokens from either OFT or OFTAdapter')
    .addParam('to', 'contract address on network B', undefined, types.string)
    .addParam('toEid', 'destination endpoint ID', undefined, types.eid)
    .addParam('amount', 'amount to transfer in token decimals', undefined, types.string)
    .setAction(async (taskArgs: Args, { ethers, deployments }) => {
        const toAddress = taskArgs.to
        const eidB = taskArgs.toEid

        // Get the contract factories
        const oftDeployment = await deployments.get('PUFFER')

        const [signer] = await ethers.getSigners()

        // Create contract instances
        const oft = new ethers.Contract(oftDeployment.address, oftDeployment.abi, signer)

        const innerTokenAddress = await oft.token()

        // Use getContractAt instead of attach for abstract contracts
        const innerToken = await ethers.getContractAt('ERC20', innerTokenAddress)

        const decimals = await innerToken.decimals()

        // If the token address !== address(this), then this is an OFT Adapter
        // if (innerTokenAddress !== oft.address) {
        //     // If the contract is OFT Adapter, get decimals from the inner token

        //     const amount = ethers.utils.parseUnits(taskArgs.amount, decimals)

        //     // Approve the amount to be spent by the oft contract
        //     const tx = await innerToken.approve(oftDeployment.address, amount)

        //     console.log(`Approved ${taskArgs.amount} tokens for spending by OFT Adapter`)

        //     // Wait 2 confirmations before doing the send
        //     await tx.wait(2)
        // }

        // lzReceive gas, comment out if you have enforced options set
        let options = Options.newOptions().addExecutorLzReceiveOption(65000, 0).toBytes()

        const sendParam: SendParam = {
            dstEid: eidB,
            to: addressToBytes32(toAddress),
            amountLD: ethers.utils.parseUnits(taskArgs.amount, decimals),
            minAmountLD: ethers.utils.parseUnits(taskArgs.amount, decimals),
            extraOptions: ethers.utils.arrayify('0x'), // set this to options variable defined above if you don't have enforced options set
            composeMsg: ethers.utils.arrayify('0x'), // Assuming no composed message
            oftCmd: ethers.utils.arrayify('0x'), // Assuming no OFT command is needed
        }
        // Get the quote for the send operation
        const feeQuote = await oft.quoteSend(sendParam, false)
        const nativeFee = feeQuote.nativeFee

        console.log(`Sending ${taskArgs.amount} token(s) to network ${getNetworkNameForEid(eidB)} (${eidB})`)

        const gasPrice = await ethers.provider.getGasPrice()
        const increasedGasPrice = gasPrice.mul(2) // Double the current gas price

        const r = await oft.send(sendParam, { nativeFee: nativeFee, lzTokenFee: 0 }, signer.address, {
            value: nativeFee,
            gasPrice: increasedGasPrice,
            // nonce:
        })
        console.log(`Send tx initiated. See: https://layerzeroscan.com/tx/${r.hash}`)
    })
