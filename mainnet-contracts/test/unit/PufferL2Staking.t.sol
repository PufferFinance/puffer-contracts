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
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { InvalidAmount } from "../../src/Errors.sol";
import { IPufLocker } from "../../src/interface/IPufLocker.sol";
import { PufLocker } from "../../src/PufLocker.sol";
import { IPufLocker } from "../../src/interface/IPufLocker.sol";

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
    /**
     * @notice EIP-712 type hash
     */
    bytes32 internal constant _MIGRATE_TYPEHASH = keccak256(
        "Migrate(address depositor,address migratorContract,address destination,address token,uint256 amount,uint256 signatureExpiry,uint256 nonce,uint256 chainId)"
    );

    PufferL2Depositor depositor;
    MockToken dai;
    MockToken sixDecimal;
    MockToken twentyTwoDecimal;
    MockToken notSupportedToken;
    PufLocker pufLocker;

    address mockMigrator;
    uint256 referralCode = 0;

    function setUp() public override {
        super.setUp();

        mockMigrator = address(new MockMigrator());
        dai = new MockToken("DAI", "DAI", 18);
        sixDecimal = new MockToken("SixDecimal", "TKN6", 6);
        twentyTwoDecimal = new MockToken("TwentyTwoDecimal", "TKN22", 22);
        notSupportedToken = new MockToken("NotSupported", "NOT", 18);

        address pufLockerImpl = address(new PufLocker());
        pufLocker = PufLocker(
            address(new ERC1967Proxy(pufLockerImpl, abi.encodeCall(PufLocker.initialize, (address(accessManager)))))
        );

        depositor = new PufferL2Depositor(address(accessManager), address(weth), pufLocker);

        // Access setup

        bytes[] memory calldatas = new bytes[](2);

        bytes4[] memory publicSelectors = new bytes4[](3);
        publicSelectors[0] = PufferL2Depositor.deposit.selector;
        publicSelectors[1] = PufferL2Depositor.depositETH.selector;
        publicSelectors[2] = PufferL2Depositor.revertIfPaused.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(depositor), publicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory multisigSelectors = new bytes4[](3);
        multisigSelectors[0] = PufferL2Depositor.setMigrator.selector;
        multisigSelectors[1] = PufferL2Depositor.addNewToken.selector;
        multisigSelectors[2] = PufferL2Depositor.setDepositCap.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(depositor),
            multisigSelectors,
            ROLE_ID_OPERATIONS_MULTISIG
        );

        // bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));
        vm.prank(address(timelock));
        accessManager.multicall(calldatas);

        // Access setup Locker

        calldatas = new bytes[](2);

        publicSelectors = new bytes4[](2);
        publicSelectors[0] = PufLocker.deposit.selector;
        publicSelectors[1] = PufLocker.withdraw.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(pufLocker), publicSelectors, PUBLIC_ROLE
        );

        multisigSelectors = new bytes4[](2);
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

        vm.startPrank(OPERATIONS_MULTISIG);

        depositor.addNewToken(address(dai));
        depositor.addNewToken(address(sixDecimal));
        depositor.addNewToken(address(twentyTwoDecimal));

        pufLocker.setLockPeriods(0, 365 days);

        pufLocker.setIsAllowedToken(depositor.tokens(address(dai)), true);
        pufLocker.setIsAllowedToken(depositor.tokens(address(sixDecimal)), true);
        pufLocker.setIsAllowedToken(depositor.tokens(address(twentyTwoDecimal)), true);
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
    function test_depositFor_dai_approve(uint32 amount, uint256 refCode) public {
        vm.assume(amount > 0);

        // This is a bad permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), "dummy domain separator");

        dai.mint(bob, amount);

        vm.startPrank(bob);

        dai.approve(address(depositor), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(dai), bob, bob, amount, refCode);
        depositor.deposit(address(dai), bob, permit, refCode, 0);

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
        emit IPufferL2Depositor.DepositedToken(address(sixDecimal), bob, bob, amount, referralCode);
        depositor.deposit(address(sixDecimal), bob, permit, referralCode, 0);

        PufToken pufToken = PufToken(depositor.tokens(address(sixDecimal)));

        assertEq(pufToken.balanceOf(bob), amount, "bob got same amount in pufToken");
        assertEq(sixDecimal.balanceOf(bob), 0, "0 token bob");

        vm.expectEmit(true, true, true, true);
        emit IPufStakingPool.Withdrawn(bob, bob, amount); // original deposit amount
        pufToken.withdraw(bob, amount);

        assertEq(sixDecimal.balanceOf(bob), amount, "bob got same amount");
        assertEq(sixDecimal.decimals(), 6, "decimals matches original token");
    }

    // Deposit & withdraw 22 decimal token
    function test_deposit_and_withdraw_twentyTwoDecimal_approve() public {
        uint256 amount = 10 ** 22;

        // This is a bad permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), "dummy domain separator");

        twentyTwoDecimal.mint(bob, amount);

        vm.startPrank(bob);
        twentyTwoDecimal.approve(address(depositor), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(twentyTwoDecimal), bob, bob, amount, referralCode);
        depositor.deposit(address(twentyTwoDecimal), bob, permit, referralCode, 0);

        PufToken pufToken = PufToken(depositor.tokens(address(twentyTwoDecimal)));

        assertEq(pufToken.balanceOf(bob), amount, "bob got same amount in pufToken");
        assertEq(twentyTwoDecimal.balanceOf(bob), 0, "0 token bob");

        vm.expectEmit(true, true, true, true);
        emit IPufStakingPool.Withdrawn(bob, bob, amount); // original deposit amount
        pufToken.withdraw(bob, amount);

        assertEq(twentyTwoDecimal.balanceOf(bob), amount, "bob got same amount");
        assertEq(twentyTwoDecimal.decimals(), 22, "decimals matches original token");
    }

    // Good Permit signature signature
    function test_depositFor_dai_permit(uint32 amount, uint256 refCode) public {
        vm.assume(amount > 0);

        // Good permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), dai.DOMAIN_SEPARATOR());

        dai.mint(bob, amount);

        vm.startPrank(bob);
        dai.approve(depositor.tokens(address(dai)), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(dai), bob, bob, amount, refCode);
        depositor.deposit(address(dai), bob, permit, refCode, 0);

        PufToken pufToken = PufToken(depositor.tokens(address(dai)));
        assertEq(pufToken.balanceOf(bob), amount, "bob got pufToken");
    }

    // Weth doesn't have `permit` at all
    function test_deposiFor_WETH(uint32 amount, uint256 refCode) public {
        vm.assume(amount > 0);

        // WETH Doesn't have permit
        Permit memory permit =
            _signPermit(_testTemps("bob", depositor.tokens(address(weth)), amount, block.timestamp), "dummy permit");

        vm.deal(bob, amount);

        vm.startPrank(bob);
        weth.deposit{ value: amount }();

        weth.approve(address(depositor), amount);

        // weth.permit triggers weth.fallback() and it doesn't revert
        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(weth), bob, bob, amount, refCode);
        depositor.deposit(address(weth), bob, permit, refCode, 0);

        PufToken pufToken = PufToken(depositor.tokens(address(weth)));
        assertEq(pufToken.balanceOf(bob), amount, "bob got pufToken");
    }

    // ETH deposit & weth withdrawal
    function test_depositFor_ETH_withdraw_weth(uint16 amount, uint256 refCode) public {
        vm.assume(amount > 0);

        vm.deal(bob, amount);

        vm.startPrank(bob);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(weth), bob, bob, amount, refCode);
        depositor.depositETH{ value: amount }(bob, refCode, 0);

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
        pufToken.deposit(bob, bob, amount);
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

    function test_migrate_with_signature() public {
        test_allow_migrator();

        uint256 amount = 1 ether;
        // has vm.startPrank inside of it
        test_direct_deposit_dai(amount);

        PufToken pufToken = PufToken(depositor.tokens(address(dai)));
        assertEq(pufToken.balanceOf(bob), amount, "bob got pufTokens");

        bytes memory signature;
        uint256 signatureExpiry = block.timestamp + 1 days;

        // Bad signature
        vm.expectRevert(IPufStakingPool.InvalidSignature.selector);
        pufToken.migrateWithSignature({
            depositor: bob,
            migratorContract: mockMigrator,
            destination: bob,
            amount: amount,
            signatureExpiry: signatureExpiry,
            stakerSignature: signature
        });

        // Expired signature
        vm.expectRevert(IPufStakingPool.ExpiredSignature.selector);
        pufToken.migrateWithSignature({
            depositor: bob,
            migratorContract: mockMigrator,
            destination: bob,
            amount: amount,
            signatureExpiry: block.timestamp - 1,
            stakerSignature: signature
        });

        // get bobs SK
        (, uint256 bobSK) = makeAddrAndKey("bob");

        bytes32 innerHash = keccak256(
            abi.encode(
                _MIGRATE_TYPEHASH, bob, mockMigrator, bob, address(dai), amount, signatureExpiry, 0, block.chainid
            )
        ); // nonce is 0
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", pufToken.DOMAIN_SEPARATOR(), innerHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobSK, outerHash);

        signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        vm.startPrank(makeAddr("bot"));
        // Automated bot can use signature from the Bob to do the migration
        pufToken.migrateWithSignature({
            depositor: bob,
            migratorContract: mockMigrator,
            destination: bob,
            amount: amount,
            signatureExpiry: signatureExpiry,
            stakerSignature: signature
        });

        assertEq(pufToken.balanceOf(bob), 0, "bob got 0 pufTokens");
        assertEq(dai.balanceOf(mockMigrator), amount, "migrator took the tokens");
    }

    // deposit unsupported token
    function testRevert_unsupported_token(uint256 amount) public {
        vm.deal(bob, 1 ether);

        // WETH Doesn't have permit
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), "dummy permit");

        vm.startPrank(bob);
        vm.expectRevert();
        depositor.deposit(address(notSupportedToken), bob, permit, referralCode, 0);
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

    // 0 ETH deposit
    function testRevert_zero_eth_deposit() public {
        vm.startPrank(bob);

        vm.expectRevert(InvalidAmount.selector);
        depositor.depositETH{ value: 0 }(bob, referralCode, 0);
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
        depositor.depositETH{ value: 1 ether }(address(0), referralCode, 0);
    }

    // 0 deposit eth reverts
    function testRevert_zero_deposit_ETH() public {
        vm.startPrank(bob);
        vm.expectRevert();
        depositor.depositETH{ value: 0 }(bob, referralCode, 0);
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

    function test_SetDepositCap() public {
        vm.startPrank(OPERATIONS_MULTISIG);
        uint256 newDepositCap = 500000 ether;
        depositor.setDepositCap(address(dai), newDepositCap);
        PufToken pufToken = PufToken(depositor.tokens(address(dai)));

        // Verify the supply cap is updated
        assertEq(pufToken.totalDepositCap(), newDepositCap, "Supply cap should be updated");
    }

    function test_depositCap_changes_with_withdrawal() public {
        // sets cap to 500000 ether
        test_SetDepositCap();

        dai.mint(bob, 5000000 ether);

        PufToken pufToken = PufToken(depositor.tokens(address(dai)));

        vm.startPrank(bob);

        dai.approve(address(pufToken), type(uint256).max);

        // deposit max amount
        vm.expectEmit(true, true, true, true);
        emit IPufStakingPool.Deposited(bob, bob, pufToken.totalDepositCap());
        pufToken.deposit(bob, bob, pufToken.totalDepositCap());

        // deposit reverts
        vm.expectRevert(IPufStakingPool.TotalDepositCapReached.selector);
        pufToken.deposit(bob, bob, 1 ether);

        // withdraw some tokens
        pufToken.withdraw(bob, 10 ether);

        // now the deposit is available again
        vm.expectEmit(true, true, true, true);
        emit IPufStakingPool.Deposited(bob, bob, 7 ether);
        pufToken.deposit(bob, bob, 7 ether);
    }

    // Deposit and lock tokens in one tx
    function test_deposit_and_lock(uint32 amount, uint256 refCode) public {
        vm.assume(amount > 0);

        // This is a bad permit signature
        Permit memory permit =
            _signPermit(_testTemps("bob", address(depositor), amount, block.timestamp), "dummy domain separator");

        dai.mint(bob, amount);

        vm.startPrank(bob);

        dai.approve(address(depositor), amount);

        vm.expectEmit(true, true, true, true);
        emit IPufferL2Depositor.DepositedToken(address(dai), bob, bob, amount, refCode);
        depositor.deposit(address(dai), bob, permit, refCode, 15); // lock for 15 seconds

        PufToken pufToken = PufToken(depositor.tokens(address(dai)));
        assertEq(pufToken.balanceOf(bob), 0, "bob did not get pufToken");

        (PufLocker.Deposit[] memory deposits) = pufLocker.getDeposits(bob, address(pufToken), 0, 1);
        assertEq(deposits.length, 1, "Should have 1 deposit");
        assertEq(deposits[0].amount, amount, "Deposit amount locked for Bob");
    }

    function testRevert_SetDepositCap_Unauthorized() public {
        // Try setting the supply cap from an unauthorized address
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        depositor.setDepositCap(address(dai), 500000 ether);
    }

    function testRevert_SetDepositCap_InvalidToken() public {
        // Try setting the supply cap for a token not in the allowlist
        vm.startPrank(OPERATIONS_MULTISIG);
        address invalidToken = address(0xabc);
        vm.expectRevert(IPufferL2Depositor.InvalidToken.selector);
        depositor.setDepositCap(invalidToken, 500000 ether);
    }

    function testRevert_SetDepositCap_BelowCurrentSupply(uint256 amount) public {
        vm.assume(amount > 0);
        // Mint some tokens to user and deposit to reach near supply cap
        vm.startPrank(bob);
        dai.mint(bob, amount);
        PufToken pufToken = PufToken(depositor.tokens(address(dai)));
        dai.approve(address(pufToken), amount);
        pufToken.deposit(bob, bob, amount);

        // Try setting the supply cap below the current total supply
        vm.startPrank(OPERATIONS_MULTISIG);
        vm.expectRevert(InvalidAmount.selector);
        depositor.setDepositCap(address(dai), amount - 1);
    }
}
