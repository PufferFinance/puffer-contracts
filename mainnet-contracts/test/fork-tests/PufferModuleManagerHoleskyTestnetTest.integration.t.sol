// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { PufferModule } from "../../src/PufferModule.sol";
import { IRestakingOperator } from "../../src/interface/IRestakingOperator.sol";
import { IPufferModuleManager } from "../../src/interface/IPufferModuleManager.sol";
import { AVSContractsRegistry } from "../../src/AVSContractsRegistry.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";
import { IStrategy } from "eigenlayer/interfaces/IStrategy.sol";
import { IBLSApkRegistry } from "eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import { IAVSDirectory } from "eigenlayer/interfaces/IAVSDirectory.sol";
import { IRewardsCoordinator } from "../../src/interface/EigenLayer/IRewardsCoordinator.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { BN254 } from "eigenlayer-middleware/libraries/BN254.sol";
import { IRegistryCoordinatorExtended } from "../../src/interface/IRegistryCoordinatorExtended.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

interface Weth {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

// PufferTestnet V1 deployment
contract PufferModuleManagerHoleskyTestnetTest is Test {
    using BN254 for BN254.G1Point;
    using Strings for uint256;

    uint256[] privKeys;
    IBLSApkRegistry.PubkeyRegistrationParams[] pubkeys;

    // https://github.com/Layr-Labs/eigenlayer-contracts?tab=readme-ov-file#deployments
    IAVSDirectory public avsDirectory = IAVSDirectory(0x055733000064333CaDDbC92763c58BF0192fFeBf);
    address EIGEN_DA_REGISTRY_COORDINATOR_HOLESKY = 0x53012C69A189cfA2D9d29eb6F19B32e0A2EA3490;
    address EIGEN_DA_SERVICE_MANAGER = 0xD4A7E1Bd8015057293f0D0A557088c286942e84b;
    address BEACON_CHAIN_STRATEGY = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;
    address EIGEN_POD_MANAGER = 0x30770d7E3e71112d7A6b7259542D1f680a70e315;
    address DELAYED_WITHDRAWAL_ROUTER = 0x642c646053eaf2254f088e9019ACD73d9AE0FA32;
    address DELEGATION_MANAGER = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;

    // Puffer Holesky deployment
    address PUFFER_SHARED_DEV_WALLET = 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;
    address ACCESS_MANAGER_HOLESKY = 0xA6c916f85DAfeb6f726E03a1Ce8d08cf835138fF;
    address MODULE_BEACON_HOLESKY = 0x5B81A4579f466fB17af4d8CC0ED51256b94c61D4;
    address PUFFER_PROTOCOL_HOLESKY = 0x705E27D6A6A0c77081D32C07DbDE5A1E139D3F14;
    address PUFFER_MODULE_MANAGER = 0xe4695ab93163F91665Ce5b96527408336f070a71;
    address PUFFER_MODULE_0_HOLESKY = 0x0B0456ec773B7D89C9deCc38b682F98556CF9862;
    // https://holesky.eigenlayer.xyz/operator/0xe2c2dc296a0bff351f6bc3e98d37ea798e393e56
    address RESTAKING_OPERATOR_CONTRACT = 0xe2c2dc296a0bFF351F6bC3e98D37ea798e393e56;
    address RESTAKING_OPERATOR_BEACON = 0xa7DC88c059F57ADcE41070cEfEFd31F74649a261;
    address REWARDS_COORDINATOR = 0xAcc1fb458a1317E886dB376Fc8141540537E68fE;

    function test_claim_undelegated_shares() public {
        // On this block number, we have already undelegated shares from the operator on chain
        // https://holesky.etherscan.io/tx/0x2d6675d7d71606a9aafcd9f0d8a65c8bad3d7c0ed7915bb67290e989a3c8f1c6#eventlog
        vm.createSelectFork(vm.rpcUrl("holesky"), 1369706);

        IPufferModuleManager pufferModuleManager = IPufferModuleManager(PUFFER_MODULE_MANAGER);

        // Upgrade PufferModule to a new implementation, that fixes the issue
        PufferModule upgrade = new PufferModule({
            protocol: PufferProtocol(payable(PUFFER_PROTOCOL_HOLESKY)),
            eigenPodManager: EIGEN_POD_MANAGER,
            delegationManager: IDelegationManager(DELEGATION_MANAGER),
            moduleManager: pufferModuleManager,
            rewardsCoordinator: IRewardsCoordinator(REWARDS_COORDINATOR)
        });

        // Execute Beacon upgrade
        vm.startPrank(PUFFER_SHARED_DEV_WALLET);
        AccessManager(ACCESS_MANAGER_HOLESKY).execute(
            MODULE_BEACON_HOLESKY, abi.encodeCall(UpgradeableBeacon.upgradeTo, address(upgrade))
        );

        // Upgrade PufferModuleManager to a new fixed implementation
        PufferModuleManager moduleManagerImplementation = new PufferModuleManager({
            pufferModuleBeacon: MODULE_BEACON_HOLESKY,
            restakingOperatorBeacon: RESTAKING_OPERATOR_BEACON,
            pufferProtocol: PUFFER_PROTOCOL_HOLESKY,
            avsContractsRegistry: new AVSContractsRegistry(ACCESS_MANAGER_HOLESKY)
        });

        // Upgrade PufferModuleManager to a new implementation
        UUPSUpgradeable(PUFFER_MODULE_MANAGER).upgradeToAndCall(address(moduleManagerImplementation), "");

        // Withdrawal data can be fetched from the transaction logs
        // cast run 0x2d6675d7d71606a9aafcd9f0d8a65c8bad3d7c0ed7915bb67290e989a3c8f1c6 --rpc-url=$HOLESKY_RPC_URL --verbose
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(BEACON_CHAIN_STRATEGY);

        uint256[] memory shares = new uint256[](1);
        shares[0] = 224000000000000000000;

        IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](1);
        withdrawals[0] = IDelegationManager.Withdrawal({
            staker: PUFFER_MODULE_0_HOLESKY,
            delegatedTo: RESTAKING_OPERATOR_CONTRACT,
            withdrawer: PUFFER_MODULE_0_HOLESKY,
            nonce: 0,
            startBlock: 1369340,
            strategies: strategies,
            shares: shares
        });

        IERC20[] memory t = new IERC20[](1);
        t[0] = IERC20(BEACON_CHAIN_STRATEGY);

        IERC20[][] memory tokens = new IERC20[][](1);
        tokens[0] = t;

        uint256[] memory middlewareTimesIndexes = new uint256[](1); // 0
        bool[] memory receiveAsTokens = new bool[](1); // false

        // At the moment the caller is the admin role, but this will be restricted to the PufferPaymaster
        pufferModuleManager.callCompleteQueuedWithdrawals({
            moduleName: bytes32("PUFFER_MODULE_0"),
            withdrawals: withdrawals,
            tokens: tokens,
            middlewareTimesIndexes: middlewareTimesIndexes,
            receiveAsTokens: receiveAsTokens
        });

        ISignatureUtils.SignatureWithExpiry memory signatureWithExpiry;
        // Delegate again to the same operator
        pufferModuleManager.callDelegateTo(
            bytes32("PUFFER_MODULE_0"), RESTAKING_OPERATOR_CONTRACT, signatureWithExpiry, bytes32(0)
        );
    }

    // Generates bls pubkey params from a private key
    function _generateBlsPubkeyParams(uint256 privKey)
        internal
        returns (IBLSApkRegistry.PubkeyRegistrationParams memory)
    {
        IBLSApkRegistry.PubkeyRegistrationParams memory pubkey;
        pubkey.pubkeyG1 = BN254.generatorG1().scalar_mul(privKey);
        pubkey.pubkeyG2 = _mulGo(privKey);
        return pubkey;
    }

    function _mulGo(uint256 x) internal returns (BN254.G2Point memory g2Point) {
        string[] memory inputs = new string[](3);
        inputs[0] = "./test/helpers/go2mul"; // lib/eigenlayer-middleware/test/ffi/go/g2mul.go binary
        inputs[1] = x.toString();

        inputs[2] = "1";
        bytes memory res = vm.ffi(inputs);
        g2Point.X[1] = abi.decode(res, (uint256));

        inputs[2] = "2";
        res = vm.ffi(inputs);
        g2Point.X[0] = abi.decode(res, (uint256));

        inputs[2] = "3";
        res = vm.ffi(inputs);
        g2Point.Y[1] = abi.decode(res, (uint256));

        inputs[2] = "4";
        res = vm.ffi(inputs);
        g2Point.Y[0] = abi.decode(res, (uint256));
    }

    /**
     * @notice internal function for calculating a signature from the operator corresponding to `_operatorPrivateKey`, delegating them to
     * the `operator`, and expiring at `expiry`.
     */
    function _getOperatorSignature(
        uint256 _operatorPrivateKey,
        address operator,
        address avs,
        bytes32 salt,
        uint256 expiry
    ) internal view returns (bytes32 digestHash, ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature) {
        operatorSignature.expiry = expiry;
        operatorSignature.salt = salt;
        {
            digestHash = avsDirectory.calculateOperatorAVSRegistrationDigestHash(operator, avs, salt, expiry);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(_operatorPrivateKey, digestHash);
            operatorSignature.signature = abi.encodePacked(r, s, v);
        }
        return (digestHash, operatorSignature);
    }
}
