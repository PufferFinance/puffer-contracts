// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PUFFER } from "../../src/PUFFER.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";

contract MockLocker {
// do nothing
}

contract PUFFERTest is UnitTestHelper {
    address owner = makeAddr("multisig");
    PUFFER public puffer;
    MockLocker public locker;

    function setUp() public override {
        puffer = new PUFFER(owner);
        locker = new MockLocker();
    }

    function test_constructor() public {
        puffer = new PUFFER(owner);
        assertEq(puffer.owner(), owner);
        assertEq(puffer.totalSupply(), 1_000_000_000 ether);
        assertEq(puffer.name(), "PUFFER");
        assertEq(puffer.symbol(), "PUFFER");
        assertEq(puffer.paused(), true, "PUFFER should be paused");
        assertEq(puffer.CLOCK_MODE(), "mode=timestamp", "Clock mode must be timestamp");
        assertEq(puffer.nonces(owner), 0, "Nonce should be 0");
    }

    function test_allowedSenderCanTransferToAnybody(address recipient) public {
        vm.assume(recipient != address(0));
        assertEq(puffer.paused(), true, "PUFFER should be paused");

        vm.startPrank(owner);
        puffer.transfer(alice, 100 ether);
        puffer.setAllowedFrom(alice, true);

        vm.startPrank(alice);

        puffer.transfer(recipient, 100 ether);

        assertEq(puffer.balanceOf(recipient), 100 ether);
    }

    function test_allowedRecipientCanReceiveTokensFromAnybody() public {
        assertEq(puffer.paused(), true, "PUFFER should be paused");

        vm.startPrank(owner);
        puffer.transfer(alice, 100 ether);
        puffer.setAllowedTo(address(locker), true);

        vm.startPrank(alice);
        puffer.transfer(address(locker), 100 ether);
        assertEq(puffer.balanceOf(address(locker)), 100 ether);
    }

    function test_onlyOwnerCanTransfer() public {
        uint256 amount = 100 ether;
        assertEq(puffer.balanceOf(alice), 0, "Alice should have 0 PUFFER");
        vm.prank(owner);
        puffer.transfer(alice, amount);
        assertEq(puffer.balanceOf(alice), amount, "Alice should have 100 PUFFER");

        vm.startPrank(alice);
        vm.expectRevert(PUFFER.TransferPaused.selector);
        puffer.transfer(bob, amount);
    }

    // Token transfer should work when the token is unpaused
    function test_unpausedTokenTransfer(uint80 aliceAmount) public {
        vm.assume(aliceAmount > 0);

        vm.startPrank(owner);
        puffer.transfer(alice, aliceAmount);

        puffer.unpause();

        vm.startPrank(alice);
        puffer.transfer(bob, aliceAmount);
        assertEq(puffer.balanceOf(bob), aliceAmount, "Bob should have 100 PUFFER");
    }
}
