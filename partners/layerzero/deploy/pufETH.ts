import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'
import { getChainConfig } from '../config'

const contractName = 'pufETH'

const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre

    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    assert(deployer, 'Missing named deployer account')

    console.log(`Network: ${hre.network.name}`)
    console.log(`Deployer: ${deployer}`)

    // Get EndpointV2 address from chain config
    const chainConfig = getChainConfig(hre.network.name)
    if (!chainConfig) {
        throw new Error(`No chain config found for network: ${hre.network.name}. Add it to config/chains/`)
    }

    const endpointV2Address = chainConfig.layerzero.endpointV2
    console.log(`EndpointV2: ${endpointV2Address}`)

    const { address, newlyDeployed } = await deploy(contractName, {
        from: deployer,
        contract: 'contracts/pufETH.sol:pufETH',
        args: [
            endpointV2Address, // LayerZero's EndpointV2 address from config
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
                contract: 'contracts/pufETH.sol:pufETH',
                address,
                constructorArguments: [
                    endpointV2Address,
                    deployer,
                ],
                force: true,
            })
            console.log(`Contract ${contractName} verified successfully`)
        } catch (error) {
            console.error(`Failed to verify contract ${contractName}:`, error)
        }
    }
}

deploy.tags = [contractName]

export default deploy
