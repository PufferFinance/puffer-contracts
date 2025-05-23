// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { RestakingOperator } from "../../src/RestakingOperator.sol";
import { RestakingOperatorController } from "../../src/RestakingOperatorController.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IPufferModuleManager } from "../../src/interface/IPufferModuleManager.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { GenerateRestakingOperatorCalldata } from
    "../../script/AccessManagerMigrations/07_GenerateRestakingOperatorCalldata.s.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { ROLE_ID_DAO } from "../../script/Roles.sol";
import { InvalidAddress, Unauthorized } from "../../src/Errors.sol";
import { AVSContractsRegistry } from "../../src/AVSContractsRegistry.sol";
import { IDelegationManager } from "../../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IAllocationManager } from "../../src/interface/Eigenlayer-Slashing/IAllocationManager.sol";
import { IRewardsCoordinator } from "../../src/interface/Eigenlayer-Slashing/IRewardsCoordinator.sol";
import { AvsRegistryCoordinatorMock } from "../mocks/AvsRegistryCoordinatorMock.sol";

contract RestakingOperatorForkTest is MainnetForkTestHelper {
    // This test is used to test the RestakingOperator contract in a forked mainnet environment
    // These are the steps taken:
    // Deploy new RestakingOperatorController
    // Add ACL to RestakingOperatorController
    // Deploy a new RestakingOperator impl (receiving the new RestakingOperatorController)
    // Upgrade RestakingOperatorBeacon
    //  Test access to RestakingOperator from PufferModuleManager and RestakingOperatorController for updateOperatorAVSSocket and customCalldataCall

    address public operatorOwner = makeAddr("operatorOwner");

    address public constant RESTAKING_OPERATOR_BEACON_ADDRESS = 0x6756B856Dd3843C84249a6A31850cB56dB824c4B;
    address public constant PUFFER_RESTAKING_OPERATOR_ADDRESS = 0x4d7C3fc856AB52753B91A6c9213aDF013309dD25;

    address public constant EIGEN_DA_ADDRESS = 0x0BAAc79acD45A023E19345c352d8a7a83C4e5656;

    address public constant AVS_CONTRACTS_REGISTRY_ADDRESS = 0x1565E55B63675c703fcC3778BD33eA97F7bE882F;
    address public constant DELEGATION_MANAGER_ADDRESS = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
    address public constant ALLOCATION_MANAGER = 0xD92145c07f8Ed1D392c1B88017934E301CC1c3Cd; // Not actual address. Irrelevant for these tests
    address public constant MODULE_MANAGER_ADDRESS = 0x9E1E4fCb49931df5743e659ad910d331735C3860;
    address public constant REWARDS_COORDINATOR_ADDRESS = 0x7750d328b314EfFa365A0402CcfD489B80B0adda;

    UpgradeableBeacon public restakingOperatorBeacon;
    RestakingOperatorController public restakingOperatorController;
    RestakingOperator public pufferRestakingOperator;
    AvsRegistryCoordinatorMock public avsRegistryCoordinatorMock;

    uint256 public expensiveRegisterFee;

    bytes4 public constant UPDATE_SOCKET_SELECTOR = bytes4(keccak256("updateSocket(string)"));

    function setUp() public virtual override {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20682408);

        // Setup contracts that are deployed to mainnet
        _setupLiveContracts();

        restakingOperatorController =
            new RestakingOperatorController(address(accessManager), AVS_CONTRACTS_REGISTRY_ADDRESS);

        // Generate calldata for RestakingOperatorController
        bytes memory controllerCalldata =
            new GenerateRestakingOperatorCalldata().run(address(restakingOperatorController));
        vm.startPrank(address(timelock));
        (bool s,) = address(accessManager).call(controllerCalldata);
        require(s, "failed setupAccess GenerateRestakingOperatorCalldata");
        vm.stopPrank();

        restakingOperatorBeacon = UpgradeableBeacon(RESTAKING_OPERATOR_BEACON_ADDRESS);

        RestakingOperator newImpl = new RestakingOperator(
            IDelegationManager(DELEGATION_MANAGER_ADDRESS),
            IAllocationManager(ALLOCATION_MANAGER),
            IPufferModuleManager(MODULE_MANAGER_ADDRESS),
            IRewardsCoordinator(REWARDS_COORDINATOR_ADDRESS),
            address(restakingOperatorController)
        );

        vm.startPrank(address(accessManager));
        vm.expectEmit(true, true, true, true);
        emit ERC1967Utils.Upgraded(address(newImpl));
        restakingOperatorBeacon.upgradeTo(address(newImpl));
        vm.stopPrank();

        pufferRestakingOperator = RestakingOperator(PUFFER_RESTAKING_OPERATOR_ADDRESS);

        vm.startPrank(OPERATIONS_MULTISIG);
        restakingOperatorController.setOperatorOwner(PUFFER_RESTAKING_OPERATOR_ADDRESS, operatorOwner);
        restakingOperatorController.setAllowedSelector(RestakingOperator.callSetClaimerFor.selector, true);
        restakingOperatorController.setAllowedSelector(RestakingOperator.customCalldataCall.selector, true);
        vm.stopPrank();

        avsRegistryCoordinatorMock = new AvsRegistryCoordinatorMock();
        expensiveRegisterFee = avsRegistryCoordinatorMock.REGISTRATION_FEE();
    }

    modifier allowUpdateOperatorAVSSocket() {
        vm.startPrank(OPERATIONS_MULTISIG);
        AVSContractsRegistry(AVS_CONTRACTS_REGISTRY_ADDRESS).setAvsRegistryCoordinator(
            EIGEN_DA_ADDRESS, UPDATE_SOCKET_SELECTOR, true
        );
        vm.stopPrank();
        _;
    }

    modifier allowExpensiveRegister() {
        vm.startPrank(OPERATIONS_MULTISIG);
        AVSContractsRegistry(AVS_CONTRACTS_REGISTRY_ADDRESS).setAvsRegistryCoordinator(
            address(avsRegistryCoordinatorMock), AvsRegistryCoordinatorMock.expensiveRegister.selector, true
        );
        vm.stopPrank();
        _;
    }

    function test_constructor() public {
        RestakingOperator newImpl;

        vm.expectRevert(InvalidAddress.selector);
        newImpl = new RestakingOperator(
            IDelegationManager(address(0)),
            IAllocationManager(ALLOCATION_MANAGER),
            IPufferModuleManager(MODULE_MANAGER_ADDRESS),
            IRewardsCoordinator(REWARDS_COORDINATOR_ADDRESS),
            address(restakingOperatorController)
        );

        vm.expectRevert(InvalidAddress.selector);
        newImpl = new RestakingOperator(
            IDelegationManager(DELEGATION_MANAGER_ADDRESS),
            IAllocationManager(address(0)),
            IPufferModuleManager(MODULE_MANAGER_ADDRESS),
            IRewardsCoordinator(REWARDS_COORDINATOR_ADDRESS),
            address(restakingOperatorController)
        );

        vm.expectRevert(InvalidAddress.selector);
        newImpl = new RestakingOperator(
            IDelegationManager(DELEGATION_MANAGER_ADDRESS),
            IAllocationManager(ALLOCATION_MANAGER),
            IPufferModuleManager(address(0)),
            IRewardsCoordinator(REWARDS_COORDINATOR_ADDRESS),
            address(restakingOperatorController)
        );

        vm.expectRevert(InvalidAddress.selector);
        newImpl = new RestakingOperator(
            IDelegationManager(DELEGATION_MANAGER_ADDRESS),
            IAllocationManager(ALLOCATION_MANAGER),
            IPufferModuleManager(MODULE_MANAGER_ADDRESS),
            IRewardsCoordinator(address(0)),
            address(restakingOperatorController)
        );

        vm.expectRevert(InvalidAddress.selector);
        newImpl = new RestakingOperator(
            IDelegationManager(DELEGATION_MANAGER_ADDRESS),
            IAllocationManager(ALLOCATION_MANAGER),
            IPufferModuleManager(MODULE_MANAGER_ADDRESS),
            IRewardsCoordinator(REWARDS_COORDINATOR_ADDRESS),
            address(0)
        );
    }

    function test_initialValues() public view {
        assertEq(address(pufferRestakingOperator.EIGEN_DELEGATION_MANAGER()), DELEGATION_MANAGER_ADDRESS);
        assertEq(address(pufferRestakingOperator.EIGEN_ALLOCATION_MANAGER()), ALLOCATION_MANAGER);
        assertEq(address(pufferRestakingOperator.PUFFER_MODULE_MANAGER()), MODULE_MANAGER_ADDRESS);
        assertEq(address(pufferRestakingOperator.EIGEN_REWARDS_COORDINATOR()), REWARDS_COORDINATOR_ADDRESS);
    }

    function test_callSetClaimerFor_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(Unauthorized.selector);
        pufferRestakingOperator.callSetClaimerFor(bob);
        vm.stopPrank();
    }

    function test_callSetClaimerFor_fromPufferModuleManager() public {
        vm.startPrank(MODULE_MANAGER_ADDRESS);
        pufferRestakingOperator.callSetClaimerFor(bob);
        vm.stopPrank();
    }

    function test_callSetClaimerFor_fromRestakingOperatorController() public {
        vm.startPrank(operatorOwner);
        bytes memory cd = abi.encodeWithSelector(RestakingOperator.callSetClaimerFor.selector, bob);
        restakingOperatorController.customExternalCall(PUFFER_RESTAKING_OPERATOR_ADDRESS, cd);
        vm.stopPrank();
    }

    function test_customCalldataCall_Unauthorized() public allowUpdateOperatorAVSSocket {
        vm.startPrank(bob);
        bytes memory cd = abi.encodeWithSelector(UPDATE_SOCKET_SELECTOR, "test");
        vm.expectRevert(Unauthorized.selector);
        pufferRestakingOperator.customCalldataCall(EIGEN_DA_ADDRESS, cd);
        vm.stopPrank();
    }

    function test_customCalldataCall_fromPufferModuleManager() public allowUpdateOperatorAVSSocket {
        vm.startPrank(MODULE_MANAGER_ADDRESS);
        bytes memory cd = abi.encodeWithSelector(UPDATE_SOCKET_SELECTOR, "test");
        pufferRestakingOperator.customCalldataCall(EIGEN_DA_ADDRESS, cd);
        vm.stopPrank();
    }

    function test_customCalldataCall_fromRestakingOperatorController() public allowUpdateOperatorAVSSocket {
        vm.startPrank(operatorOwner);
        bytes memory cdEigenDa = abi.encodeWithSelector(UPDATE_SOCKET_SELECTOR, "test");
        bytes memory cd =
            abi.encodeWithSelector(RestakingOperator.customCalldataCall.selector, EIGEN_DA_ADDRESS, cdEigenDa);
        restakingOperatorController.customExternalCall(PUFFER_RESTAKING_OPERATOR_ADDRESS, cd);
        vm.stopPrank();
    }

    function test_customCalldataCall_payable_Unauthorized() public allowExpensiveRegister {
        vm.deal(bob, expensiveRegisterFee);
        vm.startPrank(bob);
        bytes memory cd = abi.encodeWithSelector(AvsRegistryCoordinatorMock.expensiveRegister.selector, "test");
        vm.expectRevert(Unauthorized.selector);
        pufferRestakingOperator.customCalldataCall{ value: expensiveRegisterFee }(
            address(avsRegistryCoordinatorMock), cd
        );
        vm.stopPrank();
    }

    function test_customCalldataCall_payable_fromPufferModuleManager() public allowExpensiveRegister {
        vm.deal(MODULE_MANAGER_ADDRESS, expensiveRegisterFee);
        vm.startPrank(MODULE_MANAGER_ADDRESS);
        bytes memory cd = abi.encodeWithSelector(AvsRegistryCoordinatorMock.expensiveRegister.selector, "test");
        vm.expectEmit(true, true, true, true);
        emit AvsRegistryCoordinatorMock.ExpensiveRegister(
            "test", address(pufferRestakingOperator), expensiveRegisterFee
        );
        pufferRestakingOperator.customCalldataCall{ value: expensiveRegisterFee }(
            address(avsRegistryCoordinatorMock), cd
        );
        vm.stopPrank();
    }

    function test_customCalldataCall_payable_fromRestakingOperatorController() public allowExpensiveRegister {
        vm.deal(operatorOwner, expensiveRegisterFee);
        vm.startPrank(operatorOwner);
        bytes memory cdAvsMock = abi.encodeWithSelector(AvsRegistryCoordinatorMock.expensiveRegister.selector, "test");
        bytes memory cd = abi.encodeWithSelector(
            RestakingOperator.customCalldataCall.selector, address(avsRegistryCoordinatorMock), cdAvsMock
        );

        vm.expectEmit(true, true, true, true);
        emit AvsRegistryCoordinatorMock.ExpensiveRegister(
            "test", address(pufferRestakingOperator), expensiveRegisterFee
        );
        restakingOperatorController.customExternalCall{ value: expensiveRegisterFee }(
            PUFFER_RESTAKING_OPERATOR_ADDRESS, cd
        );
        vm.stopPrank();
    }
}
