// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/console.sol";
import { IntegrationTestHelper } from "../helpers/IntegrationTestHelper.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { RestakingOperator } from "../../src/RestakingOperator.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { ISignatureUtils } from "../../src/interface/Eigenlayer-Slashing/ISignatureUtils.sol";
import { IStrategyManager } from "../../src/interface/Eigenlayer-Slashing/IStrategyManager.sol";
import { IStrategy } from "../../src/interface/Eigenlayer-Slashing/IStrategy.sol";
import { IDelegationManager } from "../../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BN254 } from "../../src/interface/libraries/BN254.sol";

interface Weth {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract PufferModuleManagerIntegrationTest is IntegrationTestHelper {
    using BN254 for BN254.G1Point;
    using Strings for uint256;

    uint256[] privKeys;

    address EIGEN_DA_REGISTRY_COORDINATOR_HOLESKY = 0x53012C69A189cfA2D9d29eb6F19B32e0A2EA3490;
    address EIGEN_DA_SERVICE_MANAGER = 0xD4A7E1Bd8015057293f0D0A557088c286942e84b;
    // IAVSDirectory public avsDirectory = IAVSDirectory(0x055733000064333CaDDbC92763c58BF0192fFeBf);

    function setUp() public {
        deployContractsHolesky(0); // on latest block
    }

    function test_create_puffer_module() public {
        vm.startPrank(DAO);
        pufferProtocol.createPufferModule(bytes32("SOME_MODULE_NAME"));
    }

    function _depositToWETHEigenLayerStrategyAndDelegateTo(address restakingOperator) internal {
        // buy weth
        vm.startPrank(0xA85Fdcb45aaFF3C310a47FE309D4a35FAfbdc0ad);
        Weth(0x94373a4919B3240D86eA41593D5eBa789FEF3848).deposit{ value: 500 ether }();
        Weth(0x94373a4919B3240D86eA41593D5eBa789FEF3848)
            .approve(0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6, type(uint256).max);
        // deposit into weth strategy
        IStrategyManager(0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6)
            .depositIntoStrategy(
                IStrategy(0x80528D6e9A2BAbFc766965E0E26d5aB08D9CFaF9),
                IERC20(0x94373a4919B3240D86eA41593D5eBa789FEF3848),
                500 ether
            );

        ISignatureUtils.SignatureWithExpiry memory signatureWithExpiry;
        IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7)
            .delegateTo(restakingOperator, signatureWithExpiry, bytes32(0));
    }

    // Creates a new restaking operator and returns it
    // metadataURI is used as seed for create2 in EL
    function _createRestakingOperator() internal returns (RestakingOperator) {
        RestakingOperator operator = moduleManager.createNewRestakingOperator({
            metadataURI: "https://puffer.fi/metadata.json", allocationDelay: 0
        });

        assertTrue(address(operator).code.length > 0, "operator deployed");

        return operator;
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
