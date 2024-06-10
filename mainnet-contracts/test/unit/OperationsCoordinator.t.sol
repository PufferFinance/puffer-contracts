// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { PufferOracle } from "../../src/PufferOracle.sol";
import { OperationsCoordinator } from "../../src/OperationsCoordinator.sol";
import { ROLE_ID_OPERATIONS_PAYMASTER, ROLE_ID_OPERATIONS_MULTISIG } from "../../script/Roles.sol";

contract operationsCoordinatorTest is UnitTestHelper {
    function setUp() public override {
        super.setUp();

        vm.prank(_broadcaster);
        accessManager.grantRole(ROLE_ID_OPERATIONS_PAYMASTER, address(this), 0);

        // Set the initial price to 1 ETH
        vm.prank(DAO);
        pufferOracle.setMintPrice(1 ether);
    }

    function test_setup() public view {
        assertEq(operationsCoordinator.getPriceChangeToleranceBps(), 500, "5% is default");
        assertEq(pufferOracle.getLockedEthAmount(), 0, "locked");
        assertEq(pufferOracle.isOverBurstThreshold(), false, "burst");
    }

    function test_vt_price_change_reverts() public {
        // This contract is a 'paymaster', but the price change is too big
        vm.expectRevert(OperationsCoordinator.InvalidPrice.selector);
        operationsCoordinator.setValidatorTicketMintPrice(2 ether);
    }

    function test_vt_price_works() public {
        operationsCoordinator.setValidatorTicketMintPrice(1.01 ether);
        operationsCoordinator.setValidatorTicketMintPrice(1.02 ether);
        operationsCoordinator.setValidatorTicketMintPrice(1.03 ether);
        operationsCoordinator.setValidatorTicketMintPrice(1.04 ether);
        operationsCoordinator.setValidatorTicketMintPrice(1.05 ether);
    }

    function test_vt_price_zero() public {
        // Set the initial price to 1 wei
        vm.prank(DAO);
        pufferOracle.setMintPrice(1);

        // Zero reverts
        vm.expectRevert(OperationsCoordinator.InvalidPrice.selector);
        operationsCoordinator.setValidatorTicketMintPrice(0);
    }

    function test_percentage_change() public {
        vm.expectRevert();
        pufferOracle.setMintPrice(2 ether);

        vm.prank(_broadcaster);
        accessManager.grantRole(ROLE_ID_OPERATIONS_MULTISIG, address(this), 0);

        operationsCoordinator.setPriceChangeToleranceBps(10000);

        // 1 -> 2 eth works
        operationsCoordinator.setValidatorTicketMintPrice(2 ether);
    }
}
