// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { BaseScript } from "script/BaseScript.s.sol";
import { DeployPuffer } from "script/DeployPuffer.s.sol";
import { SetupAccess } from "script/SetupAccess.s.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { DeployPufETH, PufferDeployment } from "../script/DeployPufETH.s.sol";
import { UpgradePufETH } from "../script/UpgradePufETH.s.sol";
import { DeployPufETHBridging } from "../script/DeployPufETHBridging.s.sol";
import { DeployPufferOracle } from "script/DeployPufferOracle.s.sol";
import { PufferProtocolDeployment, BridgingDeployment } from "./DeploymentStructs.sol";
import { PufferRevenueDepositor } from "src/PufferRevenueDepositor.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { GenerateRevenueDepositorCalldata } from
    "script/AccessManagerMigrations/06_GenerateRevenueDepositorCalldata.s.sol";
import { MockAeraVault } from "test/mocks/MockAeraVault.sol";

import "forge-std/console.sol";

/**
 * @title Deploy all protocol contracts
 * @author Puffer Finance
 * @notice Deploys pufETH (upgrade it in test environment), Oracle, Puffer, and sets up the access control
 * @dev Example on how to run the script
 *      forge script script/DeployEverything.s.sol:DeployEverything --rpc-url=$RPC_URL --sig 'run(address)' $DEV_WALLET --broadcast
 * @dev Use REAL_DEPLOYMENT env to true if deploying to an actual chain (not test environment)
 */
contract DeployEverything is BaseScript {
    address DAO;

    function run(address paymaster) public returns (PufferProtocolDeployment memory, BridgingDeployment memory) {
        PufferProtocolDeployment memory deployment;

        // 1. Deploy pufETH
        // @todo In test environment, we need to deploy pufETH first, in prod, we just do the upgrade
        // AccessManager is part of the pufETH deployment
        PufferDeployment memory puffETHDeployment = new DeployPufETH().run();

        deployment.pufferVault = puffETHDeployment.pufferVault;
        deployment.pufferDepositor = puffETHDeployment.pufferDepositor;
        deployment.stETH = puffETHDeployment.stETH;
        deployment.weth = puffETHDeployment.weth;
        deployment.accessManager = puffETHDeployment.accessManager;

        address pufferOracle =
            new DeployPufferOracle().run(puffETHDeployment.accessManager, puffETHDeployment.pufferVault);

        PufferProtocolDeployment memory pufferDeployment =
            new DeployPuffer().run(puffETHDeployment.accessManager, puffETHDeployment.pufferVault, pufferOracle);

        pufferDeployment.pufferDepositor = puffETHDeployment.pufferDepositor;
        pufferDeployment.pufferVault = puffETHDeployment.pufferVault;
        pufferDeployment.stETH = puffETHDeployment.stETH;
        pufferDeployment.weth = puffETHDeployment.weth;
        pufferDeployment.timelock = puffETHDeployment.timelock;

        BridgingDeployment memory bridgingDeployment = new DeployPufETHBridging().run(puffETHDeployment);
        address revenueDepositor = _deployRevenueDepositor(puffETHDeployment);
        pufferDeployment.revenueDepositor = revenueDepositor;

        new UpgradePufETH().run(puffETHDeployment, pufferOracle, revenueDepositor);

        // `anvil` in the terminal
        if (_localAnvil) {
            DAO = _broadcaster;
        } else if (isAnvil()) {
            // Tests environment `forge test ...`
            DAO = makeAddr("DAO");
        } else {
            // Testnet deployments
            DAO = _broadcaster;
        }

        new SetupAccess().run(pufferDeployment, DAO, paymaster);

        _writeJson(pufferDeployment);

        return (pufferDeployment, bridgingDeployment);
    }

    function _writeJson(PufferProtocolDeployment memory deployment) internal {
        string memory obj = "";

        vm.serializeAddress(obj, "protocol", deployment.pufferProtocol);
        vm.serializeAddress(obj, "dao", DAO);
        vm.serializeAddress(obj, "accessManager", deployment.accessManager);
        vm.serializeAddress(obj, "moduleBeacon", deployment.beacon);
        vm.serializeAddress(obj, "moduleManager", deployment.moduleManager);
        vm.serializeAddress(obj, "validatorTicket", deployment.validatorTicket);
        vm.serializeAddress(obj, "oracle", deployment.pufferOracle);
        vm.serializeAddress(obj, "depositor", deployment.pufferDepositor);
        vm.serializeAddress(obj, "vault", deployment.pufferVault);
        vm.serializeAddress(obj, "stETH/stETH Mock", deployment.stETH);
        vm.serializeAddress(obj, "weth/weth Mock", deployment.weth);
    }

    // script/DeployRevenueDepositor.s.sol It should match the one in the script
    function _deployRevenueDepositor(PufferDeployment memory puffETHDeployment) internal returns (address) {
        MockAeraVault mockAeraVault = new MockAeraVault();

        PufferRevenueDepositor revenueDepositorImpl = new PufferRevenueDepositor({
            vault: address(puffETHDeployment.pufferVault),
            weth: address(puffETHDeployment.weth),
            aeraVault: address(mockAeraVault)
        });

        PufferRevenueDepositor revenueDepositor = PufferRevenueDepositor(
            (
                payable(
                    new ERC1967Proxy{ salt: bytes32("revenueDepositor") }(
                        address(revenueDepositorImpl),
                        abi.encodeCall(PufferRevenueDepositor.initialize, (address(puffETHDeployment.accessManager)))
                    )
                )
            )
        );

        bytes memory accessManagerCd =
            new GenerateRevenueDepositorCalldata().run(address(revenueDepositor), makeAddr("operationsMultisig"));

        vm.startPrank(puffETHDeployment.timelock);
        (bool success,) = address(puffETHDeployment.accessManager).call(accessManagerCd);
        require(success, "AccessManager.call failed");
        vm.stopPrank();

        return address(revenueDepositor);
    }
}
