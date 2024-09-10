// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PUFI } from "../../src/PUFI.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";

contract PUFITest is UnitTestHelper {
    address owner = makeAddr("multisig");
    PUFI public pufi;

    function setUp() public override {
        pufi = new PUFI(owner);
    }

    function test_constructor() public {
        pufi = new PUFI(owner);
        assertEq(pufi.owner(), owner);
        assertEq(pufi.totalSupply(), 1_000_000_000 ether);
        assertEq(pufi.name(), "PUFI");
        assertEq(pufi.symbol(), "PUFI");
    }

    // Only owner can transfer tokens while the token is paused
    function test_onlyOwnerCanTransfer() public {
        uint256 amount = 100 ether;
        assertEq(pufi.balanceOf(alice), 0, "Alice should have 0 PUFI");
        vm.prank(owner);
        pufi.transfer(alice, amount);
        assertEq(pufi.balanceOf(alice), amount, "Alice should have 100 PUFI");

        vm.startPrank(alice);
        vm.expectRevert(PUFI.PUFITransferPaused.selector);
        pufi.transfer(bob, amount);
    }

    // Token transfer should work when the token is unpaused
    function test_unpausedTokenTransfer(uint80 aliceAmount) public {
        vm.assume(aliceAmount > 0);

        vm.startPrank(owner);
        pufi.transfer(alice, aliceAmount);

        pufi.unpause();

        vm.startPrank(alice);
        pufi.transfer(bob, aliceAmount);
        assertEq(pufi.balanceOf(bob), aliceAmount, "Bob should have 100 PUFI");
    }
}
