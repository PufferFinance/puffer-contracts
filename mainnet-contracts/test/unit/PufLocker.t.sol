// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { PufLocker } from "../../src/PufLocker.sol";
import { IPufLocker } from "../../src/interface/IPufLocker.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_OPERATIONS_MULTISIG, PUBLIC_ROLE } from "../../script/Roles.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { InvalidAmount } from "../../src/Errors.sol";

contract PufLockerTest is UnitTestHelper {
    PufLocker public pufLocker;
    ERC20Mock public mockToken;

    function setUp() public override {
        super.setUp();

        mockToken = new ERC20Mock("DAI", "DAI");

        address pufLockerImpl = address(new PufLocker());
        pufLocker = PufLocker(
            address(new ERC1967Proxy(pufLockerImpl, abi.encodeCall(PufLocker.initialize, (address(accessManager)))))
        );

        // Access setup

        bytes[] memory calldatas = new bytes[](2);

        bytes4[] memory publicSelectors = new bytes4[](2);
        publicSelectors[0] = PufLocker.deposit.selector;
        publicSelectors[1] = PufLocker.withdraw.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(pufLocker), publicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory multisigSelectors = new bytes4[](2);
        multisigSelectors[0] = PufLocker.setIsAllowedToken.selector;
        multisigSelectors[1] = PufLocker.setLockPeriods.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(pufLocker),
            multisigSelectors,
            ROLE_ID_OPERATIONS_MULTISIG
        );

        // bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));
        vm.prank(address(timelock));
        accessManager.multicall(calldatas);

        // Set the lock periods
        vm.startPrank(OPERATIONS_MULTISIG);
        pufLocker.setLockPeriods(1 minutes, 1 days);
        pufLocker.setIsAllowedToken(address(mockToken), true);

        mockToken.mint(bob, 1000e18);
    }

    function test_SetAllowedToken_Success() public {
        vm.startPrank(OPERATIONS_MULTISIG);
        pufLocker.setIsAllowedToken(address(mockToken), true);

        vm.startPrank(bob);
        uint256 amount = 10e18;
        Permit memory permit =
            _signPermit(_testTemps("bob", address(pufLocker), amount, block.timestamp), mockToken.DOMAIN_SEPARATOR());

        pufLocker.deposit(address(mockToken), address(this), 61, permit); // Lock for 1 minute
    }

    function testRevert_SetAllowedToken_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        pufLocker.setIsAllowedToken(address(mockToken), true);
    }

    function test_SetLockPeriods_Success() public {
        vm.startPrank(OPERATIONS_MULTISIG);
        pufLocker.setLockPeriods(120, 172800); // Min 2 minutes, Max 2 days
        (uint128 minLock, uint128 maxLock) = pufLocker.getLockPeriods();
        assertEq(minLock, 120, "Min lock period should be 120");
        assertEq(maxLock, 172800, "Max lock period should be 172800");
    }

    function testRevert_SetLockPeriods_InvalidPeriod() public {
        vm.startPrank(OPERATIONS_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(IPufLocker.InvalidLockPeriod.selector));
        pufLocker.setLockPeriods(172800, 120); // Max less than Min
    }

    function test_Deposit_Success_WithPermit() public {
        vm.startPrank(bob);
        // Good permit signature
        uint256 amount = 10e18;
        Permit memory permit =
            _signPermit(_testTemps("bob", address(pufLocker), amount, block.timestamp), mockToken.DOMAIN_SEPARATOR());

        pufLocker.deposit(address(mockToken), bob, 3600, permit); // Lock for 1 hour
        (PufLocker.Deposit[] memory deposits) = pufLocker.getDeposits(bob, address(mockToken), 0, 1);
        assertEq(deposits.length, 1, "Should have 1 deposit");
        assertEq(deposits[0].amount, 10e18, "Deposit amount should be 100 tokens");
        vm.stopPrank();
    }

    function testRevert_Deposit_ZeroAmount() public {
        vm.startPrank(bob);
        uint256 amount = 0;
        Permit memory permit =
            _signPermit(_testTemps("bob", address(pufLocker), amount, block.timestamp), mockToken.DOMAIN_SEPARATOR());
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector));
        pufLocker.deposit(address(mockToken), bob, 3600, permit); // Lock for 1 hour with 0 amount
        vm.stopPrank();
    }

    function testRevert_Deposit_InvalidLockPeriod() public {
        vm.startPrank(bob);
        uint256 amount = 10e18;
        Permit memory permit =
            _signPermit(_testTemps("bob", address(pufLocker), amount, block.timestamp), mockToken.DOMAIN_SEPARATOR());
        vm.expectRevert(abi.encodeWithSelector(IPufLocker.InvalidLockPeriod.selector));
        pufLocker.deposit(address(mockToken), bob, 30, permit); // Lock for 30 seconds, which is less than minLockPeriod
        vm.stopPrank();
    }

    function test_Withdraw_Success() public {
        vm.startPrank(bob);
        uint256 amount = 10e18;
        Permit memory permit =
            _signPermit(_testTemps("bob", address(pufLocker), amount, block.timestamp), mockToken.DOMAIN_SEPARATOR());
        pufLocker.deposit(address(mockToken), bob, 60, permit); // Lock for 1 minute
        vm.warp(block.timestamp + 61); // Fast forward time by 61 seconds

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;
        pufLocker.withdraw(address(mockToken), indexes, bob);

        (PufLocker.Deposit[] memory deposits) = pufLocker.getDeposits(bob, address(mockToken), 0, 1);
        assertEq(deposits.length, 1, "Should have 1 deposit after withdrawal");
        assertEq(deposits[0].amount, 0, "Deposit amount should be 0 after withdrawal");
        vm.stopPrank();
    }

    function testRevert_Withdraw_DepositStillLocked() public {
        vm.startPrank(bob);
        uint256 amount = 10e18;
        Permit memory permit =
            _signPermit(_testTemps("bob", address(pufLocker), amount, block.timestamp), mockToken.DOMAIN_SEPARATOR());
        pufLocker.deposit(address(mockToken), bob, 3600, permit); // Lock for 1 hour
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(IPufLocker.DepositLocked.selector));
        pufLocker.withdraw(address(mockToken), indexes, bob); // Attempt to withdraw before lock period ends
        vm.stopPrank();
    }

    function testRevert_Withdraw_InvalidDepositIndex() public {
        vm.startPrank(bob);
        uint256 amount = 10e18;
        Permit memory permit =
            _signPermit(_testTemps("bob", address(pufLocker), amount, block.timestamp), mockToken.DOMAIN_SEPARATOR());
        pufLocker.deposit(address(mockToken), bob, 60, permit); // Lock for 1 minute
        vm.warp(block.timestamp + 61); // Fast forward time by 61 seconds

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1; // Invalid index as there is only one deposit

        vm.expectRevert(abi.encodeWithSelector(IPufLocker.InvalidDepositIndex.selector));
        pufLocker.withdraw(address(mockToken), indexes, bob);
        vm.stopPrank();
    }

    function testRevert_Withdraw_NoWithdrawableAmount() public {
        vm.startPrank(bob);
        uint256 amount = 10e18;
        Permit memory permit =
            _signPermit(_testTemps("bob", address(pufLocker), amount, block.timestamp), mockToken.DOMAIN_SEPARATOR());
        pufLocker.deposit(address(mockToken), bob, 60, permit); // Lock for 1 minute
        vm.warp(block.timestamp + 61); // Fast forward time by 61 seconds

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;

        // Withdraw once
        pufLocker.withdraw(address(mockToken), indexes, bob);

        // Try withdrawing again
        vm.expectRevert(abi.encodeWithSelector(IPufLocker.NoWithdrawableAmount.selector));
        pufLocker.withdraw(address(mockToken), indexes, bob);
        vm.stopPrank();
    }

    function test_GetDeposits_Pagination_and_getAllDeposits() public {
        vm.startPrank(bob);
        uint256 amount = 2e18;
        Permit memory permit =
            _signPermit(_testTemps("bob", address(pufLocker), amount, block.timestamp), mockToken.DOMAIN_SEPARATOR());
        pufLocker.deposit(address(mockToken), bob, 3601, permit);

        uint256 amount2 = 4e18;
        Permit memory permit2 =
            _signPermit(_testTemps("bob", address(pufLocker), amount2, block.timestamp), mockToken.DOMAIN_SEPARATOR());
        mockToken.approve(address(pufLocker), amount2);
        pufLocker.deposit(address(mockToken), bob, 3620, permit2);

        uint256 amount3 = 5e18;
        Permit memory permit3 = _signPermit(
            _testTemps("bob", address(pufLocker), amount3, block.timestamp + 2), mockToken.DOMAIN_SEPARATOR()
        );
        mockToken.approve(address(pufLocker), amount3);
        pufLocker.deposit(address(mockToken), bob, 3630, permit3);

        // Get the first 2 deposits
        PufLocker.Deposit[] memory depositsPage1 = pufLocker.getDeposits(bob, address(mockToken), 0, 2);
        assertEq(depositsPage1.length, 2, "Should return 2 deposits");

        // Get the last deposit
        PufLocker.Deposit[] memory depositsPage2 = pufLocker.getDeposits(bob, address(mockToken), 2, 1);
        assertEq(depositsPage2.length, 1, "Should return 1 deposit");
        assertEq(depositsPage2[0].amount, amount3, "Amount of the last deposit should be 50");

        // Get all deposits
        PufLocker.Deposit[] memory allDeposits = pufLocker.getAllDeposits(address(mockToken), bob);
        assertEq(allDeposits.length, 3, "Should return 3 deposits");
        assertEq(allDeposits[0].amount, amount, "Amount");
        assertEq(allDeposits[1].amount, amount2, "Amount 2");
        assertEq(allDeposits[2].amount, amount3, "Amount 3");
        vm.stopPrank();
    }
}
