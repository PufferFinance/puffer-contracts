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

    address EIGEN_DA_REGISTRY_COORDINATOR_HOODI = 0xB5b76D561eeF36CD772890C94C6Bde8b895455e2;
    address EIGEN_DA_SERVICE_MANAGER = 0x3FF2204A567C15dC3731140B95362ABb4b17d8ED;
    // IAVSDirectory public avsDirectory = IAVSDirectory(0x055733000064333CaDDbC92763c58BF0192fFeBf);

    address private constant HOODI_WETH_ADDRESS = 0x06EDa6073b3dE1B1Dfd58cb5615fD8188C114a88;
    address private constant HOODI_STRATEGY_MANAGER = 0xeE45e76ddbEDdA2918b8C7E3035cd37Eab3b5D41;
    address private constant HOODI_WETH_STRATEGY = 0x24579aD4fe83aC53546E5c2D3dF5F85D6383420d;
    address private constant HOODI_DELEGATION_MANAGER = 0x867837a9722C512e0862d8c2E15b8bE220E8b87d;

    function setUp() public {
        deployContractsHoodi(0); // on latest block
    }

    function test_create_puffer_module() public {
        vm.startPrank(DAO);
        pufferProtocol.createPufferModule(bytes32("SOME_MODULE_NAME"));
    }

    function _depositToWETHEigenLayerStrategyAndDelegateTo(address restakingOperator) internal {
        // buy weth
        vm.startPrank(0xA85Fdcb45aaFF3C310a47FE309D4a35FAfbdc0ad); // TODO Change
        Weth(HOODI_WETH_ADDRESS).deposit{ value: 500 ether }();
        Weth(HOODI_WETH_ADDRESS).approve(HOODI_STRATEGY_MANAGER, type(uint256).max);
        // deposit into weth strategy
        IStrategyManager(HOODI_STRATEGY_MANAGER).depositIntoStrategy(
            IStrategy(HOODI_WETH_STRATEGY), IERC20(HOODI_WETH_ADDRESS), 500 ether
        );

        ISignatureUtils.SignatureWithExpiry memory signatureWithExpiry;
        IDelegationManager(HOODI_DELEGATION_MANAGER).delegateTo(restakingOperator, signatureWithExpiry, bytes32(0));
    }

    // Creates a new restaking operator and returns it
    // metadataURI is used as seed for create2 in EL
    function _createRestakingOperator() internal returns (RestakingOperator) {
        RestakingOperator operator = moduleManager.createNewRestakingOperator({
            metadataURI: "https://puffer.fi/metadata.json",
            allocationDelay: 0
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
