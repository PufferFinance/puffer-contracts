// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PufferDepositor } from "../../src/PufferDepositor.sol";
import { PufferVaultV2 } from "../../src/PufferVaultV2.sol";
import { PufferVaultV2Tests } from "../../test/mocks/PufferVaultV2Tests.sol";
import { PufferDepositorV2 } from "../../src/PufferDepositorV2.sol";
import { IStETH } from "../../src/interface/Lido/IStETH.sol";
import { MockPufferOracle } from "../mocks/MockPufferOracle.sol";
import { IEigenLayer } from "../../src/interface/Eigenlayer-Slashing/IEigenLayer.sol";
import { IPufferVault } from "../../src/interface/IPufferVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { DeployPufETH } from "script/DeployPufETH.s.sol";
import { PufferDeployment } from "../../src/structs/PufferDeployment.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { PufferVault } from "../../src/PufferVault.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { IStETH } from "../../src/interface/Lido/IStETH.sol";
import { IWstETH } from "../../src/interface/Lido/IWstETH.sol";
import { ILidoWithdrawalQueue } from "../../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IEigenLayer } from "../../src/interface/Eigenlayer-Slashing/IEigenLayer.sol";
import { IStrategy } from "../../src/interface/Eigenlayer-Slashing/IStrategy.sol";
import { Timelock } from "../../src/Timelock.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";
import { GenerateAccessManagerCallData } from "script/GenerateAccessManagerCallData.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { IDelegationManager } from "../../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";

/**
 * @dev PufferDepositor and PufferVault tests (v1)
 */
contract PufferTest is Test {
    /**
     * @dev Ethereum Mainnet addresses
     */
    IStrategy internal constant _EIGEN_STETH_STRATEGY = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
    IDelegationManager internal constant _EIGEN_DELEGATION_MANGER =
        IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    IEigenLayer internal constant _EIGEN_STRATEGY_MANAGER = IEigenLayer(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);
    IStETH internal constant _ST_ETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWETH internal constant _WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IWstETH internal constant _WST_ETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ILidoWithdrawalQueue internal constant _LIDO_WITHDRAWAL_QUEUE =
        ILidoWithdrawalQueue(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

    using stdStorage for StdStorage;

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    struct _TestTemps {
        address owner;
        address to;
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 privateKey;
        uint256 nonce;
        bytes32 domainSeparator;
    }

    PufferDepositor public pufferDepositor;
    PufferVault public pufferVault;
    AccessManager public accessManager;
    Timelock public timelock;

    // Lido contract (stETH)
    IStETH stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    // EL Strategy Manager
    IEigenLayer eigenStrategyManager = IEigenLayer(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);

    address alice = makeAddr("alice");
    // Bob..
    address bob;
    uint256 bobSK;
    address charlie = makeAddr("charlie");
    address dave = makeAddr("dave");
    address eve = makeAddr("eve");

    // Use Maker address for mainnet fork tests to get wETH
    address MAKER_VAULT = 0x2F0b23f53734252Bda2277357e97e1517d6B042A;
    // Use Blast deposit contract for mainnet fork tests to get stETH
    address BLAST_DEPOSIT = 0x5F6AE08B8AeB7078cf2F96AFb089D7c9f51DA47d;

    address LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
    address LIDO_ACCOUNTING_ORACLE = 0x852deD011285fe67063a08005c71a85690503Cee;

    // Storage slot for the Consensus Layer Balance in stETH
    bytes32 internal constant CL_BALANCE_POSITION = 0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483; // keccak256("lido.Lido.beaconBalance");

    address COMMUNITY_MULTISIG;
    address OPERATIONS_MULTISIG;

    function setUp() public {
        // By forking to block 18812842, tests will start BEFORE the Lido oracle rebase
        // Lido oracle has some checks, and due to those checks when we want to rebase will roll the block number to 18819958
        vm.createSelectFork(vm.rpcUrl("mainnet"), 18812842);

        // Deploy the contracts on the fork above
        _setupContracts();
    }

    function _setupContracts() internal {
        PufferDeployment memory deployment = new DeployPufETH().run();
        pufferDepositor = PufferDepositor(payable(deployment.pufferDepositor));
        pufferVault = PufferVault(payable(deployment.pufferVault));
        accessManager = AccessManager(payable(deployment.accessManager));
        timelock = Timelock(payable(deployment.timelock));

        COMMUNITY_MULTISIG = timelock.COMMUNITY_MULTISIG();
        OPERATIONS_MULTISIG = timelock.OPERATIONS_MULTISIG();

        vm.label(COMMUNITY_MULTISIG, "COMMUNITY_MULTISIG");
        vm.label(OPERATIONS_MULTISIG, "OPERATIONS_MULTISIG");
        vm.label(address(stETH), "stETH");
        vm.label(MAKER_VAULT, "MAKER Vault");
        vm.label(0x93c4b944D05dfe6df7645A86cd2206016c51564D, "Eigen stETH strategy");

        (bob, bobSK) = makeAddrAndKey("bob");
    }

    // Transfer `token` from `from` to `to` to fill accounts in mainnet fork tests
    modifier giveToken(address from, address token, address to, uint256 amount) {
        vm.startPrank(from);
        SafeERC20.safeTransfer(IERC20(token), to, amount);
        vm.stopPrank();
        _;
    }

    modifier withCaller(address caller) {
        vm.startPrank(caller);
        _;
        vm.stopPrank();
    }

    function _increaseELstETHCap() public {
        // An example of EL increasing the cap
        // We copied the callldata from this transaction to simulate it
        // https://etherscan.io/tx/0xc16610a3dc3e8732e3fbb7761f6e1c0e44869cba5a41b058d2b3abce98833667
        vm.startPrank(0xe7fFd467F7526abf9c8796EDeE0AD30110419127); // EL
        (bool success,) = 0xBE1685C81aA44FF9FB319dD389addd9374383e90.call( // El Multisig
            hex"6a761202000000000000000000000000a6db1a8c5a981d1536266d2a393c5f8ddb210eaf00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000074000000000000000000000000000000000000000000000000000000000000005c40825f38f000000000000000000000000369e6f597e22eab55ffb173c6d9cd234bd699111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000657eb4f30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004a46a76120200000000000000000000000040a2accbd92bca938b02010e17a5b8929b49130d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000000000000000000000000000002a48d80ff0a000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002440093c4b944d05dfe6df7645a86cd2206016c51564d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004411c70c9d000000000000000000000000000000000000000000002a5a058fc295ed000000000000000000000000000000000000000000000000002a5a058fc295ed000000001bee69b7dfffa4e2d53c2a2df135c388ad25dcd20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004411c70c9d000000000000000000000000000000000000000000002a5a058fc295ed000000000000000000000000000000000000000000000000002a5a058fc295ed0000000054945180db7943c0ed0fee7edab2bd24620256bc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004411c70c9d000000000000000000000000000000000000000000002a5a058fc295ed000000000000000000000000000000000000000000000000002a5a058fc295ed00000000858646372cc42e1a627fce94aa7a7033e7cf075a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024fabc1cbc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041000000000000000000000000a6db1a8c5a981d1536266d2a393c5f8ddb210eaf00000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c30b32ae3865c0fd6cc396243889688a34f95c45a9110fe0aadc60b2a6e99e383d5d67668ffa2f5481f0003d26a5aa6b07746dd6b6162db411c585f31483efd6961b000000000000000000000000e7ffd467f7526abf9c8796edee0ad30110419127000000000000000000000000000000000000000000000000000000000000000001e3d807e6e26f9702b76782c559ef94158f44da655c8eb4e5d26f1e7cea4ef6287fa6b6da3baae46e6f8da28111d64ab62e07a0f4b80d3e418e1f8b89d62b34621c0000000000000000000000000000000000000000000000000000000000"
        );
        assertTrue(success, "oracle rebase failed");
        vm.stopPrank();
    }

    function _rebaseLido() internal {
        // Simulates stETH rebasing by fast-forwarding block 18819958 where Lido oracle rebased.  // Submits the same call data as the Lido oracle.
        // https://etherscan.io/tx/0xc308f3173b7a73b62751c42b5349203fa2684ad9b977cac5daf74582ff87d9ab
        vm.roll(18819958);
        vm.startPrank(0x140Bd8FbDc884f48dA7cb1c09bE8A2fAdfea776E); // Lido's whitelisted Oracle
        (bool success,) = LIDO_ACCOUNTING_ORACLE.call(
            hex"fc7377cd00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000007a2aff000000000000000000000000000000000000000000000000000000000004b6bb00000000000000000000000000000000000000000000000000207cc3840da37700000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000291edebdc938e7a00000000000000000000000000000000000000000000000000d37c862e1201902f400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000260000000000000000000000000000000000000000003b7c24bbc12e7a67c59354500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001af7a147aadae04565041a10836ae2210426a05e5e4d60834a4d8ebc716f2948c000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000060cb00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000004918"
        );
        assertTrue(success, "oracle rebase failed");
        vm.stopPrank();
    }

    function _finalizeWithdrawals(uint256 requestIdFinalized) internal {
        // Alter WithdrawalRouter storage slot to mark our withdrawal requests as finalized
        vm.store(
            LIDO_WITHDRAWAL_QUEUE,
            keccak256("lido.WithdrawalQueue.lastFinalizedRequestId"),
            bytes32(uint256(requestIdFinalized))
        );
    }

    function _upgradeToMainnetPuffer() internal {
        MockPufferOracle mockOracle = new MockPufferOracle();

        // Simulate that our deployed oracle becomes active and starts posting results of Puffer staking
        // At this time, we stop accepting stETH, and we accept only native ETH
        PufferVaultV2 newImplementation = new PufferVaultV2Tests(_ST_ETH, _WETH, _LIDO_WITHDRAWAL_QUEUE, mockOracle);

        // Community multisig can do thing instantly
        vm.startPrank(COMMUNITY_MULTISIG);

        //Upgrade PufferVault
        vm.expectEmit(true, true, true, true);
        emit Initializable.Initialized(2);
        UUPSUpgradeable(pufferVault).upgradeToAndCall(
            address(newImplementation), abi.encodeCall(PufferVaultV2.initialize, ())
        );

        PufferDepositorV2 newDepositorImplementation =
            new PufferDepositorV2(PufferVaultV2(payable(pufferVault)), _ST_ETH);

        // Upgrade PufferDepositor
        emit Initializable.Initialized(2);

        (bool success,) = address(timelock).call(
            abi.encodeWithSelector(
                Timelock.executeTransaction.selector,
                address(pufferDepositor),
                abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newDepositorImplementation), "")),
                1
            )
        );
        require(success, "failed upgrade tx");

        // Setup access
        bytes memory encodedMulticall =
            new GenerateAccessManagerCallData().run(address(pufferVault), address(pufferDepositor));
        // Timelock is the owner of the AccessManager
        (success,) = address(timelock).call(
            abi.encodeWithSelector(Timelock.executeTransaction.selector, address(accessManager), encodedMulticall, 1)
        );
        require(success, "failed upgrade tx");

        vm.stopPrank();
    }

    function test_lido_withdrawal_dos()
        public
        giveToken(BLAST_DEPOSIT, address(stETH), alice, 1 ether) // Blast got a lot of stETH
        giveToken(BLAST_DEPOSIT, address(stETH), address(pufferVault), 2000 ether) // Blast got a lot of stETH
        withCaller(alice)
    {
        // Alice queues a withdrawal directly on Lido and sets the PufferVault as the recipient
        uint256[] memory aliceAmounts = new uint256[](1);
        aliceAmounts[0] = 1 ether;

        SafeERC20.safeIncreaseAllowance(_ST_ETH, address(_LIDO_WITHDRAWAL_QUEUE), 1 ether);
        uint256[] memory aliceRequestIds = _LIDO_WITHDRAWAL_QUEUE.requestWithdrawals(aliceAmounts, address(pufferVault));

        // Queue 2x 1000 ETH withdrawals on Lido
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 ether; // steth Amount
        amounts[1] = 1000 ether; // steth Amount
        vm.startPrank(OPERATIONS_MULTISIG);
        uint256[] memory requestIds = pufferVault.initiateETHWithdrawalsFromLido(amounts);

        // Finalize all 3 withdrawals and fast forward to +10 days
        _finalizeWithdrawals(requestIds[1]);
        vm.roll(block.number + 10 days);

        // We try to claim the withdrawal that wasn't requested through the PufferVault
        vm.expectRevert(IPufferVault.InvalidWithdrawal.selector);
        pufferVault.claimWithdrawalsFromLido(aliceRequestIds);

        // This one should work
        pufferVault.claimWithdrawalsFromLido(requestIds);

        // 0.01% is the max delta
        assertApproxEqRel(address(pufferVault).balance, 2000 ether, 0.0001e18, "oh no");
    }

    function test_zero_stETH_deposit()
        public
        giveToken(BLAST_DEPOSIT, address(stETH), alice, 1000 ether) // Blast got a lot of stETH
        withCaller(alice)
    {
        SafeERC20.safeIncreaseAllowance(IERC20(_ST_ETH), address(pufferVault), type(uint256).max);

        uint256 minted = pufferVault.deposit(0, alice);
        assertEq(minted, 0, "got 0 back");
    }

    function test_upgrade_to_mainnet() public giveToken(MAKER_VAULT, address(_WETH), eve, 10 ether) {
        // Test pre-mainnet version
        test_minting_and_lido_rebasing();

        uint256 assetsBefore = pufferVault.totalAssets();

        // Upgrade to mainnet
        _upgradeToMainnetPuffer();

        vm.startPrank(eve);
        SafeERC20.safeIncreaseAllowance(_WETH, address(pufferVault), type(uint256).max);

        uint256 pufETHMinted = pufferVault.deposit(10 ether, eve);

        assertEq(pufferVault.totalAssets(), assetsBefore + 10 ether, "Previous assets should increase");

        PufferVaultV2(payable(address(pufferVault))).getRemainingAssetsDailyWithdrawalLimit();

        pufferVault.balanceOf(eve);
        uint256 maxWithdraw = pufferVault.maxWithdraw(eve);

        uint256 assetsValue = pufferVault.convertToAssets(pufETHMinted);
        assertApproxEqAbs(assetsValue, 10 ether, 1, "convertToAssets matches the original deposited amount");

        // IERC4626 natspec says:
        /// NOTE: any unfavorable discrepancy between convertToAssets and previewRedeem SHOULD be considered slippage in
        /// share price or some other type of condition, meaning the depositor will lose assets by redeeming.

        assertLt(maxWithdraw, pufETHMinted, "max withdraw should is smaller because of the withdrawal fee");

        pufferVault.withdraw(maxWithdraw, eve, eve);

        // Alice got less than she deposited ~ -1% less
        assertEq(_WETH.balanceOf(eve), 9.900990099009900989 ether, "eve weth after withdrawal");

        // Deposited 10 ETH, got back ~9.9 ETH
        uint256 assetsDif = 10 ether - _WETH.balanceOf(eve);

        // The rest stays in the vault
        assertEq(
            pufferVault.totalAssets(), assetsBefore + assetsDif, "should have a little more because alice got 1% less"
        );
    }

    function test_minting_and_lido_rebasing()
        public
        giveToken(BLAST_DEPOSIT, address(stETH), alice, 1000 ether) // Blast got a lot of stETH
        giveToken(BLAST_DEPOSIT, address(stETH), bob, 1000 ether)
    {
        // Pretend that alice is depositing 1k ETH
        vm.startPrank(alice);
        SafeERC20.safeIncreaseAllowance(IERC20(stETH), address(pufferVault), type(uint256).max);
        uint256 aliceMinted = pufferVault.deposit(1000 ether, alice);

        assertGt(aliceMinted, 0, "alice minted");

        // Save total ETH backing before the rebase
        uint256 backingETHAmountBefore = pufferVault.totalAssets();

        // Check the balance before rebase
        uint256 stethBalanceBefore = IERC20(stETH).balanceOf(address(pufferVault));

        _rebaseLido();

        assertTrue(pufferVault.totalAssets() > backingETHAmountBefore, "eth backing went down");

        // Check the balance after rebase and assert that it increased
        uint256 stethBalanceAfter = IERC20(stETH).balanceOf(address(pufferVault));

        assertTrue(stethBalanceAfter > stethBalanceBefore, "lido rebase failed");

        // After rebase, Bob is depositing 1k ETH
        vm.startPrank(bob);
        SafeERC20.safeIncreaseAllowance(IERC20(stETH), address(pufferVault), type(uint256).max);
        uint256 bobMinted = pufferVault.deposit(1000 ether, bob);

        // Alice should have more pufferDepositor because the rebase happened after her deposit and changed the rate
        assertTrue(aliceMinted > bobMinted, "alice should have more");

        // ETH Backing after rebase should go up
        assertTrue(pufferVault.totalAssets() > backingETHAmountBefore, "eth backing went down");
    }

    function test_depositingStETH_and_withdrawal() public {
        test_minting_and_lido_rebasing();

        // Check the balance of our vault
        uint256 balance = stETH.balanceOf(address(address(pufferVault)));

        // We deposited 2k ETH, but because of the rebase we have more than 2k
        //
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1000 ether; // steth Amount
        amounts[1] = 1000 ether; // steth Amount
        amounts[2] = balance - 2000 ether; // the test

        uint256 assetsBefore = pufferVault.totalAssets();

        // Initiate Withdrawals from lido
        vm.startPrank(OPERATIONS_MULTISIG);
        uint256[] memory requestIds = pufferVault.initiateETHWithdrawalsFromLido(amounts);

        assertApproxEqRel(assetsBefore, pufferVault.totalAssets(), 0.001e18, "bad accounting");

        // Finalize them and fast forward to +10 days
        _finalizeWithdrawals(requestIds[2]);
        vm.roll(block.number + 10 days); // stupid bug

        // Claim withdrawals
        pufferVault.claimWithdrawalsFromLido(requestIds);

        // Assert that we got more ETH than our original 2k ETH
        assertGt(address(pufferVault).balance, 2000 ether, "oh no");
    }

    function test_deposit_wstETH_permit()
        public
        giveToken(0x0B925eD163218f6662a35e0f0371Ac234f9E9371, address(_WST_ETH), alice, 3000 ether)
        withCaller(alice)
    {
        assertEq(0, pufferVault.balanceOf(alice), "alice has 0 pufETH");

        Permit memory permit = _signPermit(
            _testTemps(
                "alice",
                address(pufferDepositor),
                3000 ether,
                block.timestamp,
                hex"d4a8ff90a402dc7d4fcbf60f5488291263c743ccff180e139f47d139cedfd5fe"
            )
        );

        // Permit is good in this case
        pufferDepositor.depositWstETH(permit);

        assertGt(pufferVault.balanceOf(alice), 0, "alice got pufETH");
    }

    function test_deposit_stETH_permit()
        public
        giveToken(BLAST_DEPOSIT, address(_ST_ETH), alice, 3000 ether)
        withCaller(alice)
    {
        assertEq(0, pufferVault.balanceOf(alice), "alice has 0 pufETH");

        Permit memory permit = _signPermit(
            _testTemps(
                "alice",
                address(pufferDepositor),
                3000 ether,
                block.timestamp,
                hex"260e7e1a220ea89b9454cbcdc1fcc44087325df199a3986e560d75db18b2e253"
            )
        );

        // Permit is good in this case
        pufferDepositor.depositStETH(permit);

        assertGt(pufferVault.balanceOf(alice), 0, "alice got pufETH");
    }

    function test_deposit_wstETH()
        public
        giveToken(0x0B925eD163218f6662a35e0f0371Ac234f9E9371, address(_WST_ETH), alice, 3000 ether)
        withCaller(alice)
    {
        IERC20(address(_WST_ETH)).approve(address(pufferDepositor), type(uint256).max);

        assertEq(0, pufferVault.balanceOf(alice), "alice has 0 pufETH");

        Permit memory permit =
            _signPermit(_testTemps("alice", address(pufferDepositor), 3000 ether, block.timestamp, hex""));

        // Permit call will revert because of the bad domain separator for wstETH
        // But because we did the .approve, the transaction will succeed
        pufferDepositor.depositWstETH(permit);

        assertGt(pufferVault.balanceOf(alice), 0, "alice got pufETH");
    }

    function _signPermit(_TestTemps memory t) internal pure returns (Permit memory p) {
        bytes32 innerHash = keccak256(abi.encode(_PERMIT_TYPEHASH, t.owner, t.to, t.amount, t.nonce, t.deadline));
        bytes32 domainSeparator = t.domainSeparator;
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (t.v, t.r, t.s) = vm.sign(t.privateKey, outerHash);

        return Permit({ deadline: t.deadline, amount: t.amount, v: t.v, r: t.r, s: t.s });
    }

    function _testTemps(string memory seed, address to, uint256 amount, uint256 deadline, bytes32 domainSeparator)
        internal
        returns (_TestTemps memory t)
    {
        (t.owner, t.privateKey) = makeAddrAndKey(seed);
        t.to = to;
        t.amount = amount;
        t.deadline = deadline;
        t.domainSeparator = domainSeparator;
    }
}
