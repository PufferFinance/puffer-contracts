import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

const contractName = 'pufETHAdapter'

const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre

    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    assert(deployer, 'Missing named deployer account')

    console.log(`Network: ${hre.network.name}`)
    console.log(`Deployer: ${deployer}`)

    // This is an external deployment pulled in from @layerzerolabs/lz-evm-sdk-v2
    //
    // @layerzerolabs/toolbox-hardhat takes care of plugging in the external deployments
    // from @layerzerolabs packages based on the configuration in your hardhat config
    //
    // For this to work correctly, your network config must define an eid property
    // set to `EndpointId` as defined in @layerzerolabs/lz-definitions
    //
    // For example:
    //
    // networks: {
    //   fuji: {
    //     ...
    //     eid: EndpointId.AVALANCHE_V2_TESTNET
    //   }
    // }
    const endpointV2Deployment = await hre.deployments.get('EndpointV2')

    // The token address must be defined in hardhat.config.ts
    // If the token address is not defined, the deployment will log a warning and skip the deployment
    // if (hre.network.config.oftAdapter == null) {
    //     console.warn(`oftAdapter not configured on network config, skipping OFTWrapper deployment`)

    //     return
    // }

    const { address, newlyDeployed } = await deploy(contractName, {
        from: deployer,
        args: [
            '0xD9A442856C234a39a81a089C06451EBAa4306a72', // the basetoken address
            endpointV2Deployment.address, // LayerZero's EndpointV2 address
            deployer, // owner
        ],
        log: true,
        skipIfAlreadyDeployed: true,
    })

    console.log(`Deployed contract: ${contractName}, network: ${hre.network.name}, address: ${address}`)

    // Verify the contract if it was newly deployed
    if (newlyDeployed) {
        console.log(`Verifying contract ${contractName} on ${hre.network.name}...`)
        try {
            await hre.run('verify:verify', {
                contract: 'contracts/pufETHAdapter.sol:pufETHAdapter',
                address,
                constructorArguments: [
                    '0xD9A442856C234a39a81a089C06451EBAa4306a72', // token address
                    endpointV2Deployment.address, // LayerZero's EndpointV2 address
                    deployer, // owner
                ],
            })
            console.log(`Contract ${contractName} verified successfully`)
        } catch (error) {
            console.error(`Failed to verify contract ${contractName}:`, error)
        }
    }
}

deploy.tags = [contractName]

export default deploy
