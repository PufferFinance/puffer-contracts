// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { RestakingOperatorController } from "../../src/RestakingOperatorController.sol";
import { IRestakingOperatorController } from "../../src/interface/IRestakingOperatorController.sol";
import { RestakingOperatorMock } from "../mocks/RestakingOperatorMock.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { ROLE_ID_DAO } from "../../script/Roles.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { console } from "forge-std/console.sol";

contract RestakingOperatorControllerTest is UnitTestHelper {
    address public operator1 = makeAddr("operator1");
    address public operator2 = makeAddr("operator2");

    RestakingOperatorMock public restakingOperatorMock1;
    RestakingOperatorMock public restakingOperatorMock2;

    bytes4 constant callSetClaimerForSelector = RestakingOperatorMock.callSetClaimerFor.selector;
    bytes4 constant customCalldataCallSelector = RestakingOperatorMock.customCalldataCall.selector;

    address public AVS_REGISTRY_COORDINATOR = makeAddr("AVS_REGISTRY_COORDINATOR");
    bytes4 constant deregisterOperatorSelector = bytes4(keccak256("deregisterOperator(bytes)"));

    function setUp() public override {
        super.setUp();

        restakingOperatorMock1 = new RestakingOperatorMock(address(restakingOperatorController));
        restakingOperatorMock2 = new RestakingOperatorMock(address(restakingOperatorController));

        _skipDefaultFuzzAddresses();
    }

    modifier operatorOwner1Set() {
        vm.startPrank(DAO);
        restakingOperatorController.setOperatorOwner(address(restakingOperatorMock1), operator1);
        vm.stopPrank();
        _;
    }

    function test_setOperatorOwner_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        restakingOperatorController.setOperatorOwner(address(restakingOperatorMock1), bob);
        vm.stopPrank();
    }

    function test_setOperatorOwner_Success() public {
        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IRestakingOperatorController.OperatorOwnerUpdated(address(restakingOperatorMock1), operator1);
        restakingOperatorController.setOperatorOwner(address(restakingOperatorMock1), operator1);
        assertEq(restakingOperatorController.getOperatorOwner(address(restakingOperatorMock1)), operator1);
        vm.stopPrank();
    }

    function test_setAllowedSelector_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        restakingOperatorController.setAllowedSelector(callSetClaimerForSelector, true);
        vm.stopPrank();
    }

    function test_setAllowedSelector_Success() public {
        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IRestakingOperatorController.SelectorAllowedUpdated(callSetClaimerForSelector, true);
        restakingOperatorController.setAllowedSelector(callSetClaimerForSelector, true);
        assertEq(restakingOperatorController.isSelectorAllowed(callSetClaimerForSelector), true);

        vm.expectEmit(true, true, true, true);
        emit IRestakingOperatorController.SelectorAllowedUpdated(callSetClaimerForSelector, false);
        restakingOperatorController.setAllowedSelector(callSetClaimerForSelector, false);
        assertEq(restakingOperatorController.isSelectorAllowed(callSetClaimerForSelector), false);
        vm.stopPrank();
    }

    function test_customExternalCall_NotOperatorOwner() public {
        vm.startPrank(operator1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingOperatorController.NotOperatorOwner.selector, address(restakingOperatorMock1), operator1
            )
        );

        restakingOperatorController.customExternalCall(
            address(restakingOperatorMock1), abi.encodeWithSelector(callSetClaimerForSelector, bob), 0
        );
        vm.stopPrank();
    }

    function test_customExternalCall_NotOperatorOwner2() public operatorOwner1Set {
        vm.startPrank(operator2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingOperatorController.NotOperatorOwner.selector, address(restakingOperatorMock1), operator2
            )
        );
        restakingOperatorController.customExternalCall(
            address(restakingOperatorMock1), abi.encodeWithSelector(callSetClaimerForSelector, bob), 0
        );
        vm.stopPrank();
    }

    function test_customExternalCall_NotAllowedSelector() public operatorOwner1Set {
        vm.startPrank(operator1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingOperatorController.NotAllowedSelector.selector,
                RestakingOperatorMock.callSetClaimerFor.selector
            )
        );
        restakingOperatorController.customExternalCall(
            address(restakingOperatorMock1), abi.encodeWithSelector(callSetClaimerForSelector, bob), 0
        );
        vm.stopPrank();
    }

    function test_customExternalCall_Success() public operatorOwner1Set {
        // Allow customCalldataCall selector
        vm.startPrank(DAO);
        restakingOperatorController.setAllowedSelector(callSetClaimerForSelector, true);
        vm.stopPrank();

        vm.startPrank(operator1);
        vm.expectEmit(true, true, true, true);
        emit IRestakingOperatorController.CustomExternalCall(
            address(restakingOperatorMock1), abi.encodeWithSelector(callSetClaimerForSelector, bob), 0
        );
        restakingOperatorController.customExternalCall(
            address(restakingOperatorMock1), abi.encodeWithSelector(callSetClaimerForSelector, bob), 0
        );
        vm.stopPrank();
    }

    function test_customExternalCall_CustomCalldata_Unauthorized() public operatorOwner1Set {
        // Allow customCalldataCall selector
        vm.startPrank(DAO);
        restakingOperatorController.setAllowedSelector(customCalldataCallSelector, true);
        vm.stopPrank();

        vm.startPrank(operator1);
        bytes memory avsCalldata = abi.encodeWithSelector(deregisterOperatorSelector, bytes(""));
        vm.expectRevert(IRestakingOperatorController.Unauthorized.selector);
        restakingOperatorController.customExternalCall(
            address(restakingOperatorMock1),
            abi.encodeWithSelector(customCalldataCallSelector, AVS_REGISTRY_COORDINATOR, avsCalldata),
            0
        );
        vm.stopPrank();
    }

    function test_customExternalCall_CustomCalldata_Success() public operatorOwner1Set {
        // Allow customCalldataCall selector
        vm.startPrank(DAO);
        restakingOperatorController.setAllowedSelector(customCalldataCallSelector, true);
        // Allow deregisterOperator selector on AVS registry coordinator
        avsContractsRegistry.setAvsRegistryCoordinator(AVS_REGISTRY_COORDINATOR, deregisterOperatorSelector, true);
        vm.stopPrank();

        vm.startPrank(operator1);
        bytes memory avsCalldata = abi.encodeWithSelector(deregisterOperatorSelector, bytes(""));
        vm.expectEmit(true, true, true, true);
        emit IRestakingOperatorController.CustomExternalCall(
            address(restakingOperatorMock1),
            abi.encodeWithSelector(customCalldataCallSelector, AVS_REGISTRY_COORDINATOR, avsCalldata),
            0
        );
        restakingOperatorController.customExternalCall(
            address(restakingOperatorMock1),
            abi.encodeWithSelector(customCalldataCallSelector, AVS_REGISTRY_COORDINATOR, avsCalldata),
            0
        );
        vm.stopPrank();
    }
}
