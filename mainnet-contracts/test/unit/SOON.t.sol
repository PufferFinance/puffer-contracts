// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { CARROT } from "../../src/CARROT.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";

contract CARROTTest is UnitTestHelper {
    CARROT public soon;
    address multiSig = makeAddr("multiSig");

    function setUp() public override {
        soon = new CARROT(multiSig);
    }

    function test_constructor() public view {
        assertEq(soon.totalSupply(), 100_000_000 ether);
        assertEq(soon.name(), "Puffer Points");
        assertEq(soon.symbol(), "CARROT");
    }

    function test_initial_balance_of_multi_sig() public view {
        assertEq(soon.balanceOf(multiSig), 100_000_000 ether);
    }

    function test_transfer() public {
        vm.prank(multiSig);
        soon.transfer(alice, 1 ether);
        assertEq(soon.balanceOf(alice), 1 ether);
        assertEq(soon.balanceOf(multiSig), 99_999_999 ether);
    }

    function test_transfer_from() public {
        vm.prank(multiSig);
        soon.approve(bob, 1 ether);
        vm.prank(bob);
        soon.transferFrom(multiSig, alice, 1 ether);
        assertEq(soon.balanceOf(alice), 1 ether);
        assertEq(soon.balanceOf(multiSig), 99_999_999 ether);
    }
}
