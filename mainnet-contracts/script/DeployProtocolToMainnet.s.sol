// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { EnclaveVerifier } from "../src/EnclaveVerifier.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PufferOracleV2 } from "../src/PufferOracleV2.sol";
import { PufferModule } from "../src/PufferModule.sol";
import { RestakingOperator } from "../src/RestakingOperator.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { ValidatorTicket } from "../src/ValidatorTicket.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { IPufferOracle } from "../src/interface/IPufferOracle.sol";
import { GuardianModule } from "../src/GuardianModule.sol";
import { NoImplementation } from "../src/NoImplementation.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISlasher } from "eigenlayer/interfaces/ISlasher.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { PufferVaultV2 } from "../src/PufferVaultV2.sol";
import { PufferDepositor } from "../src/PufferDepositor.sol";
import { PufferProtocolDeployment } from "./DeploymentStructs.sol";
import { SetupAccess } from "script/SetupAccess.s.sol";
import { OperationsCoordinator } from "../src/OperationsCoordinator.sol";
import { AVSContractsRegistry } from "../src/AVSContractsRegistry.sol";
import { ValidatorTicketPricer } from "../src/ValidatorTicketPricer.sol";
import { IRewardsCoordinator } from "../src/interface/EigenLayer/IRewardsCoordinator.sol";

/**
 * // Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/DeployProtocolToMainnet.s.sol:DeployProtocolToMainnet --rpc-url=$RPC_URL --private-key $PK --vvvv
 *
 *       `forge cache clean`
 *       forge script script/DeployProtocolToMainnet.s.sol:DeployProtocolToMainnet --rpc-url=$RPC_URL --private-key $PK --broadcast
 */
contract DeployProtocolToMainnet is Script {
    UpgradeableBeacon pufferModuleBeacon;
    UpgradeableBeacon restakingOperatorBeacon;
    EnclaveVerifier verifier;
    PufferModuleManager moduleManagerImplementation;
    PufferProtocol pufferProtocolImplementation;
    GuardianModule module;
    AccessManager accessManager;
    ERC1967Proxy pufferProtocolProxy;
    ERC1967Proxy moduleManagerProxy;
    PufferModule moduleImplementation;
    RestakingOperator restakingOperatorImplementation;
    PufferOracleV2 oracle;
    OperationsCoordinator operationsCoordinator;
    PufferProtocol pufferProtocol;

    PufferVaultV2 pufferVaultV2Implementation;
    PufferDepositor pufferDepositorV2Implementation;

    ValidatorTicket validatorTicketImplementation;
    ERC1967Proxy validatorTicketProxy;

    AVSContractsRegistry aVSContractsRegistry;
    ValidatorTicketPricer validatorTicketPricer;

    // Lido
    address ST_ETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address BEACON_DEPOSIT_CONTRACT = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    // EigenLayer
    address EIGEN_POD_MANAGER = 0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338;
    address DELAYED_WITHDRAWAL_ROUTER = 0x7Fe7E9CC0F274d2435AD5d56D5fa73E47F6A23D8;
    address DELEGATION_MANAGER = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
    address EIGEN_SLASHER = 0xD92145c07f8Ed1D392c1B88017934E301CC1c3Cd;
    address STETH_STRATEGY = 0x93c4b944D05dfe6df7645A86cd2206016c51564D;
    address EIGEN_STRATEGY_MANAGER = 0x858646372CC42E1A627fcE94aa7A7033e7CF075A;

    // Existing Puffer
    address ACCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;
    address PUFFER_VAULT = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    address PUFFER_DEPOSITOR = 0x4aA799C5dfc01ee7d790e3bf1a7C2257CE1DcefF;
    address TIMELOCK = 0x3C28B7c7Ba1A1f55c9Ce66b263B33B204f2126eA;
    address DAO_MULTISIG = 0xC0896ab1A8cae8c2C1d27d011eb955Cca955580d; // Operations Multisig until the DAO is deployed

    // deployment parameters
    uint256 FRESHNESS_BLOCKS = 100; // This translates to 20 minutes
    address TREASURY = 0x946Ae7b21de3B0793Bb469e263517481B74A6950; // Safe multisig
    uint256 BPS_TREASURY_FEE_RATE = 200; // 2%
    uint256 BPS_GUARDIANS_FEE_RATE = 50; // 0.5%

    uint256 THRESHOLD = 1;
    address GUARDIAN_1 = 0xb7d83623906AC3fa577F45B7D2b9D4BD26BC5d76; // PufferDeployer
    address PAYMASTER = 0xb7d83623906AC3fa577F45B7D2b9D4BD26BC5d76; // PufferDeployer

    uint256 BPS_VT_UPDATE_PRICE_TOLERANCE = 500; // 5%

    function run() public {
        accessManager = AccessManager(ACCESS_MANAGER);

        // =================================== DOUBLE CHECK GUARDIANS ===================================
        address[] memory guardians = new address[](1);
        guardians[0] = GUARDIAN_1;

        vm.startBroadcast();

        // Enclave Verifier
        verifier = new EnclaveVerifier(FRESHNESS_BLOCKS, address(accessManager));

        // Guardian Module
        module = new GuardianModule(verifier, guardians, THRESHOLD, address(accessManager));

        // PufferOracle
        oracle = new PufferOracleV2(module, payable(PUFFER_VAULT), address(accessManager));

        operationsCoordinator =
            new OperationsCoordinator(PufferOracleV2(oracle), address(accessManager), BPS_VT_UPDATE_PRICE_TOLERANCE);

        validatorTicketPricer = new ValidatorTicketPricer(PufferOracleV2(oracle), address(accessManager));

        // Implementation of ValidatorTicket
        validatorTicketImplementation = new ValidatorTicket({
            guardianModule: payable(address(module)),
            treasury: payable(TREASURY),
            pufferVault: payable(PUFFER_VAULT),
            pufferOracle: IPufferOracle(address(oracle))
        });

        validatorTicketProxy = new ERC1967Proxy(
            address(validatorTicketImplementation),
            abi.encodeCall(
                ValidatorTicket.initialize, (address(accessManager), BPS_TREASURY_FEE_RATE, BPS_GUARDIANS_FEE_RATE)
            )
        );

        address noImpl = address(new NoImplementation());

        pufferProtocolProxy = new ERC1967Proxy(noImpl, "");
        moduleManagerProxy = new ERC1967Proxy(noImpl, "");

        moduleImplementation = new PufferModule({
            protocol: PufferProtocol(payable(pufferProtocolProxy)),
            eigenPodManager: EIGEN_POD_MANAGER,
            delegationManager: IDelegationManager(DELEGATION_MANAGER),
            moduleManager: PufferModuleManager(payable(address(moduleManagerProxy))),
            rewardsCoordinator: IRewardsCoordinator(address(0))
        });

        restakingOperatorImplementation = new RestakingOperator({
            delegationManager: IDelegationManager(DELEGATION_MANAGER),
            slasher: ISlasher(EIGEN_SLASHER),
            moduleManager: PufferModuleManager(payable(address(moduleManagerProxy))),
            rewardsCoordinator: IRewardsCoordinator(address(0))
        });

        pufferModuleBeacon = new UpgradeableBeacon(address(moduleImplementation), address(accessManager));
        restakingOperatorBeacon =
            new UpgradeableBeacon(address(restakingOperatorImplementation), address(accessManager));

        aVSContractsRegistry = new AVSContractsRegistry(address(accessManager));

        moduleManagerImplementation = new PufferModuleManager({
            pufferModuleBeacon: address(pufferModuleBeacon),
            restakingOperatorBeacon: address(restakingOperatorBeacon),
            pufferProtocol: address(pufferProtocolProxy),
            avsContractsRegistry: aVSContractsRegistry
        });

        pufferProtocolImplementation = new PufferProtocol({
            pufferVault: PufferVaultV2(payable(PUFFER_VAULT)),
            validatorTicket: ValidatorTicket(address(validatorTicketProxy)),
            guardianModule: module,
            moduleManager: address(moduleManagerProxy),
            oracle: oracle,
            beaconDepositContract: BEACON_DEPOSIT_CONTRACT
        });

        NoImplementation(payable(address(moduleManagerProxy))).upgradeToAndCall(
            address(moduleManagerImplementation),
            abi.encodeCall(moduleManagerImplementation.initialize, (address(accessManager)))
        );

        pufferProtocol = PufferProtocol(payable(address(pufferProtocolProxy)));

        NoImplementation(payable(address(pufferProtocolProxy))).upgradeToAndCall(
            address(pufferProtocolImplementation),
            abi.encodeCall(pufferProtocolImplementation.initialize, address(accessManager))
        );

        _sanityCheck();
        _writeJSON();

        // Populate the struct
        PufferProtocolDeployment memory deployment = PufferProtocolDeployment({
            pufferProtocolImplementation: address(0), // Not used in SetupAccess
            pufferProtocol: address(pufferProtocolProxy),
            guardianModule: address(module),
            accessManager: address(accessManager),
            beacon: address(pufferModuleBeacon),
            restakingOperatorBeacon: address(restakingOperatorBeacon),
            moduleManager: address(moduleManagerProxy),
            enclaveVerifier: address(verifier),
            validatorTicket: address(validatorTicketProxy),
            validatorTicketPricer: address(validatorTicketPricer),
            pufferOracle: address(oracle),
            operationsCoordinator: address(operationsCoordinator),
            aVSContractsRegistry: address(aVSContractsRegistry),
            pufferDepositor: PUFFER_DEPOSITOR,
            pufferVault: PUFFER_VAULT,
            stETH: ST_ETH,
            weth: WETH,
            timelock: TIMELOCK
        });

        new SetupAccess().run(deployment, DAO_MULTISIG, PAYMASTER);
    }

    function _writeJSON() internal {
        string memory obj = "";

        vm.serializeAddress(obj, "enclaveVerifier", address(verifier));
        vm.serializeAddress(obj, "guardianModule", address(module));
        vm.serializeAddress(obj, "oracle", address(oracle));
        vm.serializeAddress(obj, "validatorTicketProxy", address(validatorTicketProxy));
        vm.serializeAddress(obj, "validatorTicketImplementation", address(validatorTicketImplementation));
        vm.serializeAddress(obj, "pufferProtocolProxy", address(pufferProtocolProxy));
        vm.serializeAddress(obj, "pufferProtocolImplementation", address(pufferProtocolImplementation));
        vm.serializeAddress(obj, "moduleManagerProxy", address(moduleManagerProxy));
        vm.serializeAddress(obj, "moduleManagerImplementation", address(moduleManagerImplementation));
        vm.serializeAddress(obj, "pufferModuleBeacon", address(pufferModuleBeacon));
        vm.serializeAddress(obj, "pufferModuleImplementation", address(moduleImplementation));
        vm.serializeAddress(obj, "restakingOperatorBeacon", address(restakingOperatorBeacon));
        vm.serializeAddress(obj, "restakingOperatorImplementation", address(restakingOperatorImplementation));

        string memory finalJson = vm.serializeString(obj, "", "");
        vm.writeJson(finalJson, "./output/protocol-mainnet.json");
    }

    function _sanityCheck() internal view {
        ValidatorTicket vt = ValidatorTicket(address(validatorTicketProxy));

        require(vt.TREASURY() == TREASURY, "treasury");
        require(vt.GUARDIAN_MODULE() == address(module), "guardian module");
        require(vt.PUFFER_VAULT() == PUFFER_VAULT, "vault");
        require(address(vt.PUFFER_ORACLE()) == address(oracle), "oracle");
        require(vt.getProtocolFeeRate() == 200, "protocol fee rate 2%");
    }
}
