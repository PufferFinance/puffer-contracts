// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/console.sol";
import { IntegrationTestHelper } from "../helpers/IntegrationTestHelper.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { IRestakingOperator } from "../../src/interface/IRestakingOperator.sol";
import { IPufferModuleManager } from "../../src/interface/IPufferModuleManager.sol";
import { RestakingOperator } from "../../src/RestakingOperator.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";
import { IStrategyManager } from "eigenlayer/interfaces/IStrategyManager.sol";
import { IStrategy } from "eigenlayer/interfaces/IStrategy.sol";
import { IBLSApkRegistry, IRegistryCoordinator } from "eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import { IAVSDirectory } from "eigenlayer/interfaces/IAVSDirectory.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { BN254 } from "eigenlayer-middleware/libraries/BN254.sol";
import { IRegistryCoordinatorExtended } from "../../src/interface/IRegistryCoordinatorExtended.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Weth {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract PufferModuleManagerIntegrationTest is IntegrationTestHelper {
    using BN254 for BN254.G1Point;
    using Strings for uint256;

    uint256[] privKeys;
    IBLSApkRegistry.PubkeyRegistrationParams[] pubkeys;

    address EIGEN_DA_REGISTRY_COORDINATOR_HOLESKY = 0x53012C69A189cfA2D9d29eb6F19B32e0A2EA3490;
    address EIGEN_DA_SERVICE_MANAGER = 0xD4A7E1Bd8015057293f0D0A557088c286942e84b;
    IAVSDirectory public avsDirectory = IAVSDirectory(0x055733000064333CaDDbC92763c58BF0192fFeBf);

    function setUp() public {
        deployContractsHolesky(0); // on latest block
    }

    function test_create_puffer_module() public {
        vm.startPrank(DAO);
        pufferProtocol.createPufferModule(bytes32("SOME_MODULE_NAME"));
    }

    // function test_opt_into_slashing() public {
    //     vm.startPrank(DAO);
    //     IRestakingOperator operator = _createRestakingOperator();

    //     address slasher = address(1235);

    //     vm.expectEmit(true, true, true, true);
    //     emit IPufferModuleManager.RestakingOperatorOptedInSlasher(address(operator), slasher);
    //     moduleManager.callOptIntoSlashing(operator, slasher);
    // }

    // function test_modify_operator() public {
    //     vm.startPrank(DAO);
    //     IRestakingOperator operator = _createRestakingOperator();

    //     IDelegationManager.OperatorDetails memory newOperatorDetails = IDelegationManager.OperatorDetails({
    //         __deprecated_earningsReceiver: address(this),
    //         delegationApprover: address(0),
    //         stakerOptOutWindowBlocks: 100
    //     });

    //     vm.expectEmit(true, true, true, true);
    //     emit IPufferModuleManager.RestakingOperatorModified(address(operator), newOperatorDetails);
    //     moduleManager.callModifyOperatorDetails({ restakingOperator: operator, newOperatorDetails: newOperatorDetails });

    //     IDelegationManager.OperatorDetails memory details =
    //         operator.EIGEN_DELEGATION_MANAGER().operatorDetails(address(operator));
    //     assertEq(details.stakerOptOutWindowBlocks, 100, "updated blocks");

    //     assertEq(details.__deprecated_earningsReceiver, address(this), "updated earnings");
    // }

    // function test_update_metadata_uri() public {
    //     vm.startPrank(DAO);
    //     IRestakingOperator operator = _createRestakingOperator();

    //     string memory newUri = "https://puffer.fi/updated.json";

    //     vm.expectEmit(true, true, true, true);
    //     emit IPufferModuleManager.RestakingOperatorMetadataURIUpdated(address(operator), newUri);
    //     moduleManager.callUpdateMetadataURI(operator, newUri);
    // }

    // Don't remove this test, it is used as a reference for real registration
    // function test_eigenda_avs() public {
    // This test is for the Existing Holesky Testnet deployment

    // // vm.startPrank(DAO);
    // // https://holesky.eigenlayer.xyz/operator/0xe2c2dc296a0bff351f6bc3e98d37ea798e393e56
    // address restakingOperator = 0xe2c2dc296a0bFF351F6bC3e98D37ea798e393e56;
    // // IRestakingOperator restakingOperator = _createRestakingOperator();

    // // _depositToWETHEigenLayerStrategyAndDelegateTo(address(restakingOperator));

    // IBLSApkRegistry.PubkeyRegistrationParams memory params = _generateBlsPubkeyParams(vm.envUint("OPERATOR_BLS_SK"));

    // // He signs with his BLS key the message to register him with our Restaking Operator contract
    // BN254.G1Point memory messageHash = IRegistryCoordinatorExtended(EIGEN_DA_REGISTRY_COORDINATOR_HOLESKY)
    //     .pubkeyRegistrationMessageHash(address(restakingOperator));

    // params.pubkeyRegistrationSignature = BN254.scalar_mul(messageHash, vm.envUint("OPERATOR_BLS_SK"));

    // (bytes32 digestHash, ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature) =
    // _getOperatorSignature(
    //     vm.envUint("OPERATOR_ECDSA_SK"),
    //     address(restakingOperator),
    //     EIGEN_DA_SERVICE_MANAGER,
    //     bytes32(hex"aaaa"),
    //     type(uint256).max
    // );

    // address operatorAddress = vm.addr(vm.envUint("OPERATOR_ECDSA_SK"));

    // IPufferModuleManager pufferModuleManager = IPufferModuleManager(0xe4695ab93163F91665Ce5b96527408336f070a71);

    // vm.startPrank(0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0);

    // bytes memory hashCall = abi.encodeCall(
    //     IPufferModuleManager.updateAVSRegistrationSignatureProof,
    //     (IRestakingOperator(restakingOperator), digestHash, operatorAddress)
    // );

    // //@todo has to be updated manually on the contract
    // /// cast send 0xe4695ab93163F91665Ce5b96527408336f070a71 0xd82752c8000000000000000000000000e2c2dc296a0bff351f6bc3e98d37ea798e393e5653db2c4483378e8f37899e656561460562547c3f6a840a33f3c02f4c4f608eca000000000000000000000000454c063b1d5dfa8e0ebb4e4198cff1101dda5d2c --rpc-url=$HOLESKY_RPC_URL --private-key=$PUFFER_SHARED_PK
    // console.log("hash call:");
    // console.logBytes(hashCall);

    // // pufferModuleManager.updateAVSRegistrationSignatureProof(
    // //     IRestakingOperator(restakingOperator), digestHash, operatorAddress
    // // );

    // IRegistryCoordinator.OperatorKickParam[] memory operatorKickParams =
    //     new IRegistryCoordinator.OperatorKickParam[](1);
    // operatorKickParams[0] = IRegistryCoordinator.OperatorKickParam({
    //     quorumNumber: 1,
    //     operator: 0xCE9AdA2dE1d94e62ca3574383a8F562B572dbC6C
    // });
    // ISignatureUtils.SignatureWithSaltAndExpiry memory churnApproverSignature;
    // churnApproverSignature.signature =
    //     hex"9df0fa39818eec0a3a1dd9bb639dff0b98df88f82523d3f41d20611667681f83021adc47e5fe20e40de7650649b1385b8f14b824973a60eea95b560f98ce0ce81c";
    // churnApproverSignature.salt = hex"a930fd8d687e85d9957a4462b472e6a25d9f7c8b2fb639604da2f670a1f13512";
    // churnApproverSignature.expiry = 1712919092;

    // bytes memory calldataToRegister = abi.encodeCall(
    //     IPufferModuleManager.callRegisterOperatorToAVSWithChurn,
    //     (
    //         IRestakingOperator(restakingOperator),
    //         EIGEN_DA_REGISTRY_COORDINATOR_HOLESKY,
    //         bytes(hex"01"),
    //         "20.64.16.29:32005;32004",
    //         params,
    //         operatorKickParams,
    //         churnApproverSignature,
    //         operatorSignature
    //     )
    // );

    // console.log("Calldata to register operator to AVS, submit to PufferModuleManager:");
    // console.logBytes(calldataToRegister);

    // // Finish the registration
    // (bool success,) = address(pufferModuleManager).call(calldataToRegister);
    // assertEq(success, true, "register operator to avs");

    // 4. Dao registers the operator by submitting his signature to the AVS
    // pufferModuleManager.callRegisterOperatorToAVSWithChurn({
    //     restakingOperator: IRestakingOperator(restakingOperator),
    //     avsRegistryCoordinator: EIGEN_DA_REGISTRY_COORDINATOR_HOLESKY,
    //     quorumNumbers: bytes(hex"01"),
    //     socket: "103.199.107.52:32005;32004",
    //     params: params,
    //     operatorSignature: operatorSignature,
    //     operatorKickParams: operatorKickParams,
    //     churnApproverSignature: churnApproverSignature
    // });
    // }

    function _depositToWETHEigenLayerStrategyAndDelegateTo(address restakingOperator) internal {
        // buy weth
        vm.startPrank(0xA85Fdcb45aaFF3C310a47FE309D4a35FAfbdc0ad);
        Weth(0x94373a4919B3240D86eA41593D5eBa789FEF3848).deposit{ value: 500 ether }();
        Weth(0x94373a4919B3240D86eA41593D5eBa789FEF3848).approve(
            0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6, type(uint256).max
        );
        // deposit into weth strategy
        IStrategyManager(0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6).depositIntoStrategy(
            IStrategy(0x80528D6e9A2BAbFc766965E0E26d5aB08D9CFaF9),
            IERC20(0x94373a4919B3240D86eA41593D5eBa789FEF3848),
            500 ether
        );

        ISignatureUtils.SignatureWithExpiry memory signatureWithExpiry;
        IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7).delegateTo(
            restakingOperator, signatureWithExpiry, bytes32(0)
        );
    }

    // Creates a new restaking operator and returns it
    // metadataURI is used as seed for create2 in EL
    function _createRestakingOperator() internal returns (IRestakingOperator) {
        IRestakingOperator operator = moduleManager.createNewRestakingOperator({
            metadataURI: "https://puffer.fi/metadata.json",
            delegationApprover: address(0),
            stakerOptOutWindowBlocks: 0
        });

        IDelegationManager.OperatorDetails memory details =
            operator.EIGEN_DELEGATION_MANAGER().operatorDetails(address(operator));
        assertEq(details.delegationApprover, address(0), "delegation approver");
        assertEq(details.stakerOptOutWindowBlocks, 0, "blocks");
        assertEq(details.__deprecated_earningsReceiver, address(moduleManager), "earnings receiver");

        return operator;
    }

    function _generateOperatorKeys() internal returns (uint256, IBLSApkRegistry.PubkeyRegistrationParams memory) {
        uint256 privKey = uint256(keccak256(abi.encodePacked("secretPrivateKey")));

        IBLSApkRegistry.PubkeyRegistrationParams memory pubkey;
        pubkey.pubkeyG1 = BN254.generatorG1().scalar_mul(privKey);
        pubkey.pubkeyG2 = _mulGo(privKey);

        return (privKey, pubkey);
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
}
