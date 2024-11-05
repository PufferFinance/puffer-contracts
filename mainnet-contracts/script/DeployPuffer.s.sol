// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferProtocol } from "../src/PufferProtocol.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { NoImplementation } from "../src/NoImplementation.sol";
import { PufferModule } from "../src/PufferModule.sol";
import { RestakingOperator } from "../src/RestakingOperator.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { EigenPodManagerMock } from "../test/mocks/EigenPodManagerMock.sol";
import { DelegationManagerMock } from "../test/mocks/DelegationManagerMock.sol";
import { BeaconMock } from "../test/mocks/BeaconMock.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISlasher } from "eigenlayer/interfaces/ISlasher.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PufferVaultV2 } from "../src/PufferVaultV2.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { GuardiansDeployment, PufferProtocolDeployment } from "./DeploymentStructs.sol";
import { ValidatorTicket } from "../src/ValidatorTicket.sol";
import { ValidatorTicketPricer } from "../src/ValidatorTicketPricer.sol";
import { OperationsCoordinator } from "../src/OperationsCoordinator.sol";
import { PufferOracleV2 } from "../src/PufferOracleV2.sol";
import { IPufferOracleV2 } from "../src/interface/IPufferOracleV2.sol";
import { IRewardsCoordinator } from "../src/interface/EigenLayer/IRewardsCoordinator.sol";
import { AVSContractsRegistry } from "../src/AVSContractsRegistry.sol";
import { RewardsCoordinatorMock } from "../test/mocks/RewardsCoordinatorMock.sol";

/**
 * @title DeployPuffer
 * @author Puffer Finance
 * @notice Deploys PufferProtocol Contracts
 * @dev
 *
 *
 *         NOTE:
 *
 *         If you ran the deployment script, but did not `--broadcast` the transaction, it will still update your local chainId-deployment.json file.
 *         Other scripts will fail because addresses will be updated in deployments file, but the deployment never happened.
 *
 *
 *         forge script script/DeployPuffer.s.sol:DeployPuffer -vvvv --rpc-url=$EPHEMERY_RPC_URL --broadcast
 */
contract DeployPuffer is BaseScript {
    PufferProtocol pufferProtocolImpl;
    AccessManager accessManager;
    ERC1967Proxy proxy;
    ERC1967Proxy validatorTicketProxy;
    ERC1967Proxy moduleManagerProxy;
    PufferProtocol pufferProtocol;
    UpgradeableBeacon pufferModuleBeacon;
    UpgradeableBeacon restakingOperatorBeacon;
    PufferModuleManager moduleManager;
    OperationsCoordinator operationsCoordinator;
    ValidatorTicketPricer validatorTicketPricer;
    AVSContractsRegistry aVSContractsRegistry;

    address eigenPodManager;
    address delegationManager;
    address rewardsCoordinator;
    address eigenSlasher;
    address treasury;
    address operationsMultisig;

    function run(GuardiansDeployment calldata guardiansDeployment, address pufferVault, address oracle)
        public
        broadcast
        returns (PufferProtocolDeployment memory)
    {
        accessManager = AccessManager(guardiansDeployment.accessManager);

        if (isMainnet()) {
            // Mainnet / Mainnet fork
            eigenPodManager = 0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338;
            delegationManager = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
            eigenSlasher = 0xD92145c07f8Ed1D392c1B88017934E301CC1c3Cd;
            rewardsCoordinator = address(0); //@todo
            treasury = vm.envAddress("TREASURY");
            operationsMultisig = 0xC0896ab1A8cae8c2C1d27d011eb955Cca955580d;
        } else if (isAnvil()) {
            // Local chain / tests
            eigenPodManager = address(new EigenPodManagerMock());
            delegationManager = address(new DelegationManagerMock());
            rewardsCoordinator = address(new RewardsCoordinatorMock());
            eigenSlasher = vm.envOr("EIGEN_SLASHER", address(1)); // @todo
            treasury = address(1);
            operationsMultisig = address(2);
        } else {
            // Holesky https://github.com/Layr-Labs/eigenlayer-contracts?tab=readme-ov-file#current-testnet-deployment
            eigenPodManager = 0x30770d7E3e71112d7A6b7259542D1f680a70e315;
            delegationManager = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
            eigenSlasher = 0xcAe751b75833ef09627549868A04E32679386e7C;
            treasury = 0x61A44645326846F9b5d9c6f91AD27C3aD28EA390;
            rewardsCoordinator = 0xAcc1fb458a1317E886dB376Fc8141540537E68fE;
            operationsMultisig = 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;
        }

        operationsCoordinator = new OperationsCoordinator(PufferOracleV2(oracle), address(accessManager), 500); // 500 BPS = 5%
        validatorTicketPricer = new ValidatorTicketPricer(PufferOracleV2(oracle), address(accessManager));

        validatorTicketProxy = new ERC1967Proxy(address(new NoImplementation()), "");
        ValidatorTicket validatorTicketImplementation = new ValidatorTicket({
            guardianModule: payable(guardiansDeployment.guardianModule),
            treasury: payable(treasury),
            pufferVault: payable(pufferVault),
            pufferOracle: IPufferOracleV2(oracle),
            operationsMultisig: operationsMultisig
        });

        NoImplementation(payable(address(validatorTicketProxy))).upgradeToAndCall(
            address(validatorTicketImplementation),
            abi.encodeCall(
                ValidatorTicket.initialize,
                (address(accessManager), 500, 50) //@todo recheck 5% treasury, 0.5% guardians
            )
        );

        // UUPS proxy for PufferProtocol
        proxy = new ERC1967Proxy(address(new NoImplementation()), "");
        {
            // Deploy empty proxy for PufferModuleManager
            // We need it to have it as immutable in PufferModule
            moduleManagerProxy = new ERC1967Proxy(address(new NoImplementation()), "");

            PufferModule moduleImplementation = new PufferModule({
                protocol: PufferProtocol(payable(proxy)),
                eigenPodManager: eigenPodManager,
                delegationManager: IDelegationManager(delegationManager),
                moduleManager: PufferModuleManager(payable(address(moduleManagerProxy))),
                rewardsCoordinator: IRewardsCoordinator(rewardsCoordinator)
            });
            vm.label(address(moduleImplementation), "PufferModuleImplementation");

            RestakingOperator restakingOperatorImplementation = new RestakingOperator(
                IDelegationManager(delegationManager),
                ISlasher(eigenSlasher),
                PufferModuleManager(payable(address(moduleManagerProxy))),
                IRewardsCoordinator(rewardsCoordinator)
            );

            pufferModuleBeacon = new UpgradeableBeacon(address(moduleImplementation), address(accessManager));
            restakingOperatorBeacon =
                new UpgradeableBeacon(address(restakingOperatorImplementation), address(accessManager));

            aVSContractsRegistry = new AVSContractsRegistry(address(accessManager));

            // Puffer Service implementation
            pufferProtocolImpl = new PufferProtocol({
                pufferVault: PufferVaultV2(payable(pufferVault)),
                validatorTicket: ValidatorTicket(address(validatorTicketProxy)),
                guardianModule: GuardianModule(payable(guardiansDeployment.guardianModule)),
                moduleManager: address(moduleManagerProxy),
                oracle: IPufferOracleV2(oracle),
                beaconDepositContract: getStakingContract()
            });
        }

        pufferProtocol = PufferProtocol(payable(address(proxy)));

        NoImplementation(payable(address(proxy))).upgradeToAndCall(address(pufferProtocolImpl), "");

        moduleManager = new PufferModuleManager({
            pufferModuleBeacon: address(pufferModuleBeacon),
            restakingOperatorBeacon: address(restakingOperatorBeacon),
            pufferProtocol: address(proxy),
            avsContractsRegistry: aVSContractsRegistry
        });

        NoImplementation(payable(address(moduleManagerProxy))).upgradeToAndCall(
            address(moduleManager), abi.encodeCall(moduleManager.initialize, (address(accessManager)))
        );

        // Initialize the Pool
        pufferProtocol.initialize({ accessManager: address(accessManager) });

        vm.label(address(accessManager), "AccessManager");
        vm.label(address(operationsCoordinator), "OperationsCoordinator");
        vm.label(address(validatorTicketProxy), "ValidatorTicketProxy");
        vm.label(address(validatorTicketImplementation), "ValidatorTicketImplementation");
        vm.label(address(proxy), "PufferProtocolProxy");
        vm.label(address(pufferProtocolImpl), "PufferProtocolImplementation");
        vm.label(address(moduleManagerProxy), "PufferModuleManager");
        vm.label(address(pufferModuleBeacon), "PufferModuleBeacon");
        vm.label(address(guardiansDeployment.enclaveVerifier), "EnclaveVerifier");
        vm.label(address(guardiansDeployment.enclaveVerifier), "EnclaveVerifier");

        // return (pufferProtocol, pool, accessManager);
        return PufferProtocolDeployment({
            validatorTicket: address(validatorTicketProxy),
            validatorTicketPricer: address(validatorTicketPricer),
            pufferProtocolImplementation: address(pufferProtocolImpl),
            pufferProtocol: address(proxy),
            guardianModule: guardiansDeployment.guardianModule,
            accessManager: guardiansDeployment.accessManager,
            enclaveVerifier: guardiansDeployment.enclaveVerifier,
            beacon: address(pufferModuleBeacon),
            restakingOperatorBeacon: address(restakingOperatorBeacon),
            moduleManager: address(moduleManagerProxy),
            pufferOracle: address(oracle),
            operationsCoordinator: address(operationsCoordinator),
            aVSContractsRegistry: address(aVSContractsRegistry),
            timelock: address(0), // overwritten in DeployEverything
            stETH: address(0), // overwritten in DeployEverything
            pufferVault: address(0), // overwritten in DeployEverything
            pufferDepositor: address(0), // overwritten in DeployEverything
            weth: address(0), // overwritten in DeployEverything
            revenueDepositor: address(0) // overwritten in DeployEverything
         });
    }

    function getStakingContract() internal returns (address) {
        // Mainnet
        if (isMainnet()) {
            return 0x00000000219ab540356cBB839Cbe05303d7705Fa;
        }

        // Goerli
        if (block.chainid == 5) {
            return 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b;
        }

        // Holesky
        if (block.chainid == 17000) {
            return 0x4242424242424242424242424242424242424242;
        }

        // Tests / local chain
        if (isAnvil()) {
            return address(new BeaconMock());
        }

        // Ephemery
        return 0x4242424242424242424242424242424242424242;
    }
}
