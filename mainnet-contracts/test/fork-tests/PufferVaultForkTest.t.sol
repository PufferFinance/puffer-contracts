// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { IPufferVault } from "../../src/interface/IPufferVault.sol";
import { IPufferVaultV2 } from "../../src/interface/IPufferVaultV2.sol";

/**
 * @notice For some reason the code coverage doesn't consider that this mainnet fork tests increase the code coverage..
 */
contract PufferVaultForkTest is MainnetForkTestHelper {
    function setUp() public virtual override { }

    // In this test, we initiate ETH withdrawal from Lido
    function test_initiateETHWithdrawalsFromLido() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21549844); // Jan-04-2025 08:13:23 AM +UTC
        _setupLiveContracts();

        vm.startPrank(_getOPSMultisig());

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        uint256[] memory requestIds = pufferVault.initiateETHWithdrawalsFromLido(amounts);
        requestIds[0] = 66473; // That is the next request id for this test

        vm.expectEmit(true, true, true, true);
        emit IPufferVault.RequestedWithdrawals(requestIds);
        pufferVault.initiateETHWithdrawalsFromLido(amounts);
    }

    // In this test, we claim some queued withdrawal from Lido
    function test_claimETHWithdrawalsFromLido() public {
        // Different fork
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21378494); // Dec-11-2024 09:52:59 AM +UTC
        _setupLiveContracts();

        vm.startPrank(_getOPSMultisig());

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 62744; // That is the next request id for this test

        uint256 balanceBefore = address(pufferVault).balance;

        vm.expectEmit(true, true, true, true);
        emit IPufferVault.ClaimedWithdrawals(requestIds);
        pufferVault.claimWithdrawalsFromLido(requestIds);

        uint256 balanceAfter = address(pufferVault).balance;
        assertEq(balanceAfter, balanceBefore + 107.293916980728143835 ether, "Balance should increase by ~107 ether");
    }

    // Prevent deposit and withdraw in the same transaction
    function test_depositAndWithdrawRevertsInTheSameTx() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21378494); // Dec-11-2024 09:52:59 AM +UTC
        _setupLiveContracts();

        vm.deal(alice, 1 ether);
        vm.startPrank(alice);

        pufferVault.depositETH{ value: 1 ether }(alice);

        vm.expectRevert(IPufferVaultV2.DepositAndWithdrawalForbidden.selector);
        pufferVault.redeem(1 ether, alice, alice);
    }
}
