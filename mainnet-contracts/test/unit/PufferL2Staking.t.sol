// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { PufferL2Depositor } from "../../src/PufferL2Depositor.sol";
import { PufToken } from "../../src/PufToken.sol";
import { IMigrator } from "../../src/interface/IMigrator.sol";
import { IPufStakingPool } from "../../src/interface/IPufStakingPool.sol";
import { IPufferL2Depositor } from "../../src/interface/IPufferL2Depositor.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_OPERATIONS_MULTISIG, PUBLIC_ROLE } from "../../script/Roles.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockToken is ERC20, ERC20Permit {
    uint8 _dec; // decimals

    constructor(string memory tokenName, string memory tokenSymbol, uint8 dec)
        ERC20(tokenName, tokenSymbol)
        ERC20Permit(tokenName)
    {
        _dec = dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }
}

contract MockMigrator is IMigrator {
    using SafeERC20 for ERC20;

    function migrate(address, address, uint256 amount) external {
        // Transfer the tokens here
        PufToken(msg.sender).TOKEN().safeTransferFrom(msg.sender, address(this), amount);
    }
}

contract PufferL2Staking is UnitTestHelper {
    PufferL2Depositor depositor;
    MockToken dai;
    MockToken sixDecimal;
    MockToken twentyTwoDecimal;
    MockToken notSupportedToken;

    address mockMigrator;

    address bob = makeAddr("bob");

    function setUp() public override {
        super.setUp();

        mockMigrator = address(new MockMigrator());
        dai = new MockToken("DAI", "DAI", 18);
        sixDecimal = new MockToken("SixDecimal", "TKN6", 6);
        twentyTwoDecimal = new MockToken("TwentyTwoDecimal", "TKN22", 22);
        notSupportedToken = new MockToken("NotSupported", "NOT", 18);

        depositor = new PufferL2Depositor(address(accessManager), address(weth));

        // Access setup

        bytes[] memory calldatas = new bytes[](2);

        bytes4[] memory publicSelectors = new bytes4[](3);
        publicSelectors[0] = PufferL2Depositor.deposit.selector;
        publicSelectors[1] = PufferL2Depositor.depositETH.selector;
        publicSelectors[2] = PufferL2Depositor.revertIfPaused.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(depositor), publicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory multisigSelectors = new bytes4[](2);
        multisigSelectors[0] = PufferL2Depositor.setMigrator.selector;
        multisigSelectors[1] = PufferL2Depositor.addNewToken.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(depositor),
            multisigSelectors,
            ROLE_ID_OPERATIONS_MULTISIG
        );

        // bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));
        vm.prank(address(timelock));
        accessManager.multicall(calldatas);

        vm.startPrank(OPERATIONS_MULTISIG);

        depositor.addNewToken(address(dai));
        depositor.addNewToken(address(sixDecimal));
        depositor.addNewToken(address(twentyTwoDecimal));
    }

    function test_setup() public view {
        assertTrue(depositor.tokens(address(weth)) != address(0), "bad weth address");
        assertTrue(depositor.tokens(address(dai)) != address(0), "bad dai address");
        assertTrue(depositor.tokens(address(sixDecimal)) != address(0), "bad sixDecimal address");
        assertTrue(depositor.tokens(address(twentyTwoDecimal)) != address(0), "bad twentyTwoDecimal address");
    }

    function test_setMigrator(address migrator, bool allowed) public {
        vm.assume(migrator != address(0));

        vm.startPrank(OPERATIONS_MULTISIG);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.SetIsMigratorAllowed(migrator, allowed);
        depositor.setMigrator(migrator, allowed);

        assertEq(depositor.isAllowedMigrator(migrator), allowed, "bad migrator status");
    }

    // Bad permit signature + approve
    function test_depositFor_dai_approve(uint32 amount) public {
        vm.assume(amount > 0);

        // This is a bad permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), "dummy domain separator");

        dai.mint(bob, amount);

        vm.startPrank(bob);
        dai.approve(address(depositor), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(dai), bob, bob, amount);
        depositor.deposit(address(dai), bob, permit);

        PufToken pufToken = PufToken(depositor.tokens(address(dai)));
        assertEq(pufToken.balanceOf(bob), amount, "bob got pufToken");
    }

    // Deposit & withdraw 6 decimal token
    function test_deposit_and_withdraw_sixDecimal_approve() public {
        uint256 amount = 10 ** 6;

        // This is a bad permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), "dummy domain separator");

        sixDecimal.mint(bob, amount);

        vm.startPrank(bob);
        sixDecimal.approve(address(depositor), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(sixDecimal), bob, bob, amount);
        depositor.deposit(address(sixDecimal), bob, permit);

        PufToken pufToken = PufToken(depositor.tokens(address(sixDecimal)));

        assertEq(pufToken.balanceOf(bob), 1 ether, "bob got 1 eth pufToken");
        assertEq(sixDecimal.balanceOf(bob), 0, "0 token bob");

        vm.expectEmit(true, true, true, true);
        emit IPufStakingPool.Withdrawn(bob, bob, amount); // original deposit amount
        pufToken.withdraw(bob, 1 ether);
    }

    // Deposit & withdraw 22 decimal token
    function test_deposit_and_withdraw_22Decimal_approve() public {
        uint256 amount = 10 ** 22;

        // This is a bad permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), "dummy domain separator");

        twentyTwoDecimal.mint(bob, amount);

        vm.startPrank(bob);
        twentyTwoDecimal.approve(address(depositor), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(twentyTwoDecimal), bob, bob, amount);
        depositor.deposit(address(twentyTwoDecimal), bob, permit);

        PufToken pufToken = PufToken(depositor.tokens(address(twentyTwoDecimal)));

        assertEq(pufToken.balanceOf(bob), 1 ether, "bob got 1 eth pufToken");
        assertEq(twentyTwoDecimal.balanceOf(bob), 0, "0 token bob");

        vm.expectEmit(true, true, true, true);
        emit IPufStakingPool.Withdrawn(bob, bob, amount); // original deposit amount
        pufToken.withdraw(bob, 1 ether);
    }

    // Good Permit signature signature
    function test_depositFor_dai_permit(uint32 amount) public {
        vm.assume(amount > 0);

        // Good permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), dai.DOMAIN_SEPARATOR());

        dai.mint(bob, amount);

        vm.startPrank(bob);
        dai.approve(address(depositor), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(dai), bob, bob, amount);
        depositor.deposit(address(dai), bob, permit);

        PufToken pufToken = PufToken(depositor.tokens(address(dai)));
        assertEq(pufToken.balanceOf(bob), amount, "bob got pufToken");
    }

    // Weth doesn't have `permit` at all
    function test_deposiFor_WETH(uint32 amount) public {
        vm.assume(amount > 0);

        // WETH Doesn't have permit
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), "dummy permit");

        vm.deal(bob, amount);

        vm.startPrank(bob);
        weth.deposit{ value: amount }();

        weth.approve(address(depositor), amount);

        // weth.permit triggers weth.fallback() and it doesn't revert
        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(weth), bob, bob, amount);
        depositor.deposit(address(weth), bob, permit);

        PufToken pufToken = PufToken(depositor.tokens(address(weth)));
        assertEq(pufToken.balanceOf(bob), amount, "bob got pufToken");
    }

    // ETH deposit & weth withdrawal
    function test_depositFor_ETH_withdraw_weth(uint16 amount) public {
        vm.assume(amount > 0);

        vm.deal(bob, amount);

        vm.startPrank(bob);
        dai.approve(address(depositor), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(weth), bob, bob, amount);
        depositor.depositETH{ value: amount }(bob);

        PufToken pufToken = PufToken(depositor.tokens(address(weth)));
        assertEq(pufToken.balanceOf(bob), amount, "bob got pufToken");

        vm.expectEmit(true, true, true, true);
        emit IPufStakingPool.Withdrawn(bob, bob, amount);
        pufToken.withdraw(bob, amount);
    }
    // direct deposit to the token contract, without using the depositor

    function test_direct_deposit_dai(uint256 amount) public {
        vm.assume(amount > 0);
        dai.mint(bob, amount);

        PufToken pufToken = PufToken(depositor.tokens(address(dai)));

        vm.startPrank(bob);

        dai.approve(address(pufToken), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufStakingPool.Deposited(bob, bob, amount);
        pufToken.deposit(bob, amount);
    }

    // Allow migrator
    function test_allow_migrator() public {
        vm.startPrank(OPERATIONS_MULTISIG);

        assertEq(depositor.isAllowedMigrator(mockMigrator), false, "migrator not allowed");
        depositor.setMigrator(mockMigrator, true);
        assertEq(depositor.isAllowedMigrator(mockMigrator), true, "migrator allowed");
    }

    function test_migrate_works() public {
        test_allow_migrator();

        uint256 amount = 1 ether;
        // has vm.startPrank inside of it
        test_direct_deposit_dai(amount);

        PufToken pufToken = PufToken(depositor.tokens(address(dai)));
        assertEq(pufToken.balanceOf(bob), amount, "bob got pufTokens");

        pufToken.migrate(amount, mockMigrator, bob);

        assertEq(pufToken.balanceOf(bob), 0, "bob got 0 pufTokens");
        assertEq(dai.balanceOf(mockMigrator), amount, "migrator took the tokens");
    }

    // function test_migrate_with_signature() public {
    //     test_allow_migrator();

    //     uint256 amount = 1 ether;
    //     // has vm.startPrank inside of it
    //     test_direct_deposit_dai(amount);

    //     PufToken pufToken = PufToken(depositor.tokens(address(dai)));
    //     assertEq(pufToken.balanceOf(bob), amount, "bob got pufTokens");

    //     pufToken.migrate(amount, mockMigrator, bob);

    //     assertEq(pufToken.balanceOf(bob), 0, "bob got 0 pufTokens");
    //     assertEq(dai.balanceOf(mockMigrator), amount, "migrator took the tokens");
    // }

    // deposit unsuported token
    function testRevert_unsuported_token(uint256 amount) public {
        vm.deal(bob, 1 ether);

        // WETH Doesn't have permit
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), "dummy permit");

        vm.startPrank(bob);
        vm.expectRevert();
        depositor.deposit(address(notSupportedToken), bob, permit);
    }

    // zero address token reverts
    function testRevert_addNewToken_zero_address() public {
        vm.startPrank(OPERATIONS_MULTISIG);

        vm.expectRevert();
        depositor.addNewToken(address(0));
    }

    // zero address migrator reverts
    function testRevert_setMigrator_zero_address() public {
        vm.startPrank(OPERATIONS_MULTISIG);

        vm.expectRevert();
        depositor.setMigrator(address(0), true);
    }

    // zero address migrator reverts
    function testRevert_migrate_with_zero_address_migrator() public {
        PufToken pufToken = PufToken(depositor.tokens(address(weth)));

        vm.expectRevert(abi.encodeWithSelector(IPufStakingPool.MigratorContractNotAllowed.selector, address(0)));
        pufToken.migrate(500, address(0), bob);
    }

    // Mock address 123 is not allowed to be migrator
    function testRevert_migrate_with_contract_that_is_not_allowed() public {
        PufToken pufToken = PufToken(depositor.tokens(address(weth)));

        vm.expectRevert();
        pufToken.migrate(500, address(123), bob);
    }

    // deposit to zero address
    function testRevert_zero_address_deposit_ETH() public {
        vm.deal(bob, 1 ether);
        vm.startPrank(bob);
        vm.expectRevert();
        depositor.depositETH{ value: 1 ether }(address(0));
    }

    // 0 deposit eth reverts
    function testRevert_zero_deposit_ETH() public {
        vm.startPrank(bob);
        vm.expectRevert();
        depositor.depositETH{ value: 0 }(bob);
    }

    // No deposit reverts
    function testRevert_withdrawal_without_deposit(uint256 amount) public {
        PufToken pufToken = PufToken(depositor.tokens(address(weth)));
        vm.expectRevert();
        pufToken.withdraw(address(weth), amount);
    }

    // 0 amount reverts
    function testRevert_withdrawal_without_deposit_reverts() public {
        PufToken pufToken = PufToken(depositor.tokens(address(weth)));
        vm.expectRevert();
        pufToken.withdraw(address(weth), 0);
    }
}
