// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { SOON } from "../../src/SOON.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";

contract SOONTest is UnitTestHelper {
    SOON public soon;
    address multiSig = makeAddr("multiSig");

    function setUp() public override {
        soon = new SOON(multiSig);
    }

    function test_constructor() public view {
        assertEq(soon.totalSupply(), 250_000_000 ether);
        assertEq(soon.name(), "Puffer Points");
        assertEq(soon.symbol(), "SOON");
    }

    function test_initial_balance_of_multi_sig() public view {
        assertEq(soon.balanceOf(multiSig), 250_000_000 ether);
    }

    function test_transfer() public {
        vm.prank(multiSig);
        soon.transfer(alice, 1 ether);
        assertEq(soon.balanceOf(alice), 1 ether);
        assertEq(soon.balanceOf(multiSig), 249_999_999 ether);
    }

    function test_transfer_from() public {
        vm.prank(multiSig);
        soon.approve(bob, 1 ether);
        vm.prank(bob);
        soon.transferFrom(multiSig, alice, 1 ether);
        assertEq(soon.balanceOf(alice), 1 ether);
        assertEq(soon.balanceOf(multiSig), 249_999_999 ether);
    }
}
