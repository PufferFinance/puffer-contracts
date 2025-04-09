// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { CARROT } from "../../src/CARROT.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";

contract CARROTTest is UnitTestHelper {
    CARROT public carrot;
    address multiSig = makeAddr("multiSig");

    function setUp() public override {
        carrot = new CARROT(multiSig);
    }

    function test_constructor() public view {
        assertEq(carrot.totalSupply(), 100_000_000 ether);
        assertEq(carrot.name(), "Carrot");
        assertEq(carrot.symbol(), "CARROT");
    }

    function test_initial_balance_of_multi_sig() public view {
        assertEq(carrot.balanceOf(multiSig), 100_000_000 ether);
    }

    function test_transfer() public {
        vm.prank(multiSig);
        carrot.transfer(alice, 1 ether);
        assertEq(carrot.balanceOf(alice), 1 ether);
        assertEq(carrot.balanceOf(multiSig), 99_999_999 ether);
    }

    function test_transfer_from() public {
        vm.prank(multiSig);
        carrot.approve(bob, 1 ether);
        vm.prank(bob);
        carrot.transferFrom(multiSig, alice, 1 ether);
        assertEq(carrot.balanceOf(alice), 1 ether);
        assertEq(carrot.balanceOf(multiSig), 99_999_999 ether);
    }
}
