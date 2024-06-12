// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { PufferL2StakingPool } from "../../src/PufferL2StakingPool.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_OPERATIONS_MULTISIG, PUBLIC_ROLE } from "../../script/Roles.sol";
import { Permit } from "../../src/structs/Permit.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockToken is ERC20, ERC20Permit {
    constructor(string memory tokenName, string memory tokenSymbol)
        ERC20(tokenName, tokenSymbol)
        ERC20Permit(tokenName)
    { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PufferL2StakingPoolTest is UnitTestHelper {
    PufferL2StakingPool stakingPool;
    MockToken dai;
    MockToken ben;

    address bob = makeAddr("bob");

    function setUp() public override {
        super.setUp();

        dai = new MockToken("DAI", "DAI");
        ben = new MockToken("BenjaminToken", "BEN");

        address[] memory allowedTokens = new address[](3);
        allowedTokens[0] = address(weth);
        allowedTokens[1] = address(dai);
        allowedTokens[2] = address(ben);

        stakingPool = new PufferL2StakingPool(address(accessManager), allowedTokens, address(weth));

        // Access setup

        bytes[] memory calldatas = new bytes[](2);

        bytes4[] memory publicSelectors = new bytes4[](4);
        publicSelectors[0] = PufferL2StakingPool.depositFor.selector;
        publicSelectors[1] = PufferL2StakingPool.depositETHFor.selector;
        publicSelectors[2] = PufferL2StakingPool.migrate.selector;
        publicSelectors[3] = PufferL2StakingPool.migrateWithSig.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(stakingPool), publicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory multisigSelectors = new bytes4[](2);
        multisigSelectors[0] = PufferL2StakingPool.setTokenAllowed.selector;
        multisigSelectors[1] = PufferL2StakingPool.setMigrator.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(stakingPool),
            multisigSelectors,
            ROLE_ID_OPERATIONS_MULTISIG
        );

        // bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));
        vm.prank(address(timelock));
        accessManager.multicall(calldatas);
    }

    function test_setup() public view {
        assertEq(stakingPool.WETH(), address(weth), "bad weth address");
        assertEq(stakingPool.tokenAllowlist(address(weth)), true, "token should be allowed 0");
        assertEq(stakingPool.tokenAllowlist(address(dai)), true, "token should be allowed 1");
        assertEq(stakingPool.tokenAllowlist(address(ben)), true, "token should be allowed 2");
    }

    function test_setTokenIsAllowed(address token, bool allowed) public {
        vm.assume(token != address(0));

        vm.startPrank(OPERATIONS_MULTISIG);

        vm.expectEmit(true, true, true, true);
        emit PufferL2StakingPool.SetIsTokenAllowed(token, allowed);
        stakingPool.setTokenAllowed(token, allowed);

        assertEq(stakingPool.tokenAllowlist(token), allowed, "bad token status");
    }

    function test_setMigrator(address migrator, bool allowed) public {
        vm.assume(migrator != address(0));

        vm.startPrank(OPERATIONS_MULTISIG);

        vm.expectEmit(true, true, true, true);
        emit PufferL2StakingPool.SetIsMigratorAllowed(migrator, allowed);
        stakingPool.setMigrator(migrator, allowed);

        assertEq(stakingPool.allowedMigrators(migrator), allowed, "bad migrator status");
    }

    // Bad permit signature + approve
    function test_depositFor_dai_approve(uint16 amount) public {
        vm.assume(amount > 0);

        // This is a bad permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(stakingPool), amount, block.timestamp), "dummy domain separator");

        dai.mint(bob, amount);

        vm.startPrank(bob);
        dai.approve(address(stakingPool), amount);

        vm.expectEmit(true, true, true, true);
        emit PufferL2StakingPool.Deposited(bob, address(dai), amount);
        stakingPool.depositFor(address(dai), bob, permit);
    }

    // Good Permit signature signature
    function test_depositFor_dai_permit(uint16 amount) public {
        vm.assume(amount > 0);

        // Good permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(stakingPool), amount, block.timestamp), dai.DOMAIN_SEPARATOR());

        dai.mint(bob, amount);

        vm.startPrank(bob);
        dai.approve(address(stakingPool), amount);

        vm.expectEmit(true, true, true, true);
        emit PufferL2StakingPool.Deposited(bob, address(dai), amount);
        stakingPool.depositFor(address(dai), bob, permit);
    }

    // Weth doesn't have `permit` at all
    function test_deposiFor_WETH(uint16 amount) public {
        vm.assume(amount > 0);

        // WETH Doesn't have permit
        Permit memory permit =
            _signPermit(_testTemps("bob", address(stakingPool), amount, block.timestamp), "dummy permit");

        vm.deal(bob, amount);

        vm.startPrank(bob);
        weth.deposit{ value: amount }();

        weth.approve(address(stakingPool), amount);

        // weth.permit triggers weth.fallback() and it doesn't revert
        vm.expectEmit(true, true, true, true);
        emit PufferL2StakingPool.Deposited(bob, address(weth), amount);
        stakingPool.depositFor(address(weth), bob, permit);
    }

    // ETH deposit & weth withdrawal
    function test_depositFor_ETH_withdraw_weth(uint16 amount) public {
        vm.assume(amount > 0);

        vm.deal(bob, amount);

        vm.startPrank(bob);
        dai.approve(address(stakingPool), amount);

        vm.expectEmit(true, true, true, true);
        emit PufferL2StakingPool.Deposited(bob, address(weth), amount);
        stakingPool.depositETHFor{ value: amount }(bob);

        vm.expectEmit(true, true, true, true);
        emit PufferL2StakingPool.Withdrawn(bob, address(weth), amount);
        stakingPool.withdraw(address(weth), amount);
    }

    // deposit to zero address
    function testRevert_zero_address_deposit_ETH() public {
        vm.deal(bob, 1 ether);
        vm.startPrank(bob);
        vm.expectRevert();
        stakingPool.depositETHFor{ value: 1 ether }(address(0));
    }

    // deposit to zero address
    function testRevert_zero_address_deposit_ETH() public {
        vm.deal(bob, 1 ether);
        vm.startPrank(bob);
        vm.expectRevert();
        stakingPool.depositETHFor{ value: 1 ether }(address(0));
    }

    // 0 deposit eth reverts
    function testRevert_zero_deposit_ETH() public {
        vm.startPrank(bob);
        vm.expectRevert();
        stakingPool.depositETHFor{ value: 0 }(bob);
    }

    // No deposit reverts
    function testRevert_withdrawal_without_deposit(uint256 amount) public {
        vm.expectRevert();
        stakingPool.withdraw(address(weth), amount);
    }

    // 0 amount reverts
    function testRevert_withdrawal_without_deposit_reverts() public {
        vm.expectRevert();
        stakingPool.withdraw(address(weth), 0);
    }
}
