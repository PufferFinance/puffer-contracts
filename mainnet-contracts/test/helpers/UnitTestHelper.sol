// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { BaseScript } from "../../script/BaseScript.s.sol";
import { PufferOracleV2 } from "../../src/PufferOracleV2.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { AVSContractsRegistry } from "../../src/AVSContractsRegistry.sol";
import { RestakingOperatorController } from "../../src/RestakingOperatorController.sol";
import { RaveEvidence } from "../../src/struct/RaveEvidence.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { DeployEverything } from "../../script/DeployEverything.s.sol";
import { PufferProtocolDeployment, BridgingDeployment } from "../../script/DeploymentStructs.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { PufferDepositor } from "../../src/PufferDepositor.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { stETHMock } from "../mocks/stETHMock.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { ValidatorTicketPricer } from "../../src/ValidatorTicketPricer.sol";
import { OperationsCoordinator } from "../../src/OperationsCoordinator.sol";
// import { xPufETH } from "src/l2/xPufETH.sol";
// import { XERC20Lockbox } from "src/XERC20Lockbox.sol";
import { L1RewardManager } from "src/L1RewardManager.sol";
import { PufferRevenueDepositor } from "src/PufferRevenueDepositor.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
// import { ConnextMock } from "../mocks/ConnextMock.sol";
import { pufETHAdapter } from "partners-layerzero/contracts/pufETHAdapter.sol";
import { pufETH } from "partners-layerzero/contracts/pufETH.sol";
import {
    ROLE_ID_DAO,
    ROLE_ID_OPERATIONS_PAYMASTER,
    ROLE_ID_OPERATIONS_MULTISIG,
    ROLE_ID_LOCKBOX
} from "../../script/Roles.sol";
import { GenerateSlashingELCalldata } from "../../script/AccessManagerMigrations/07_GenerateSlashingELCalldata.s.sol";

contract UnitTestHelper is Test, BaseScript {
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
    }

    bytes32 public constant PUFFER_MODULE_0 = bytes32("PUFFER_MODULE_0");
    address public constant ADDRESS_ZERO = address(0);
    address public constant ADDRESS_ONE = address(1);
    address public constant ADDRESS_CHEATS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    // Addresses that are supposed to be skipped when fuzzing
    mapping(address fuzzedAddress => bool isFuzzed) internal fuzzedAddressMapping;

    PufferDepositor public pufferDepositor;
    PufferVaultV5 public pufferVault;
    stETHMock public stETH;
    IWETH public weth;

    PufferProtocol public pufferProtocol;
    UpgradeableBeacon public beacon;
    PufferModuleManager public pufferModuleManager;
    ValidatorTicket public validatorTicket;
    PufferOracleV2 public pufferOracle;

    AccessManager public accessManager;
    OperationsCoordinator public operationsCoordinator;
    AVSContractsRegistry public avsContractsRegistry;
    RestakingOperatorController public restakingOperatorController;
    ValidatorTicketPricer public validatorTicketPricer;
    // xPufETH public xpufETH;
    // XERC20Lockbox public lockBox;
    L1RewardManager public l1RewardManager;
    L2RewardManager public l2RewardManager;
    PufferRevenueDepositor public revenueDepositor;
    // pufETH public pufETHOFT;
    // pufETHAdapter public pufETHOFTAdapter;
    address public layerzeroL1Endpoint;
    address public layerzeroL2Endpoint;
    // ConnextMock public connext;

    address public DAO = makeAddr("DAO");
    address public PAYMASTER = makeAddr("PUFFER_PAYMASTER"); // 0xA540f91Fb840381BCCf825a16A9fbDD0a19deFB1
    address public l2RewardsManagerMock = makeAddr("l2RewardsManagerMock");
    address public timelock;

    address LIQUIDITY_PROVIDER = makeAddr("LIQUIDITY_PROVIDER");

    // We use the same values in DeployPufETH.s.sol
    address public COMMUNITY_MULTISIG = makeAddr("communityMultisig");
    address public OPERATIONS_MULTISIG = makeAddr("operationsMultisig");

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public dianna = makeAddr("dianna");
    address public ema = makeAddr("ema");
    address public filip = makeAddr("filip");
    address public george = makeAddr("george");
    address public harry = makeAddr("harry");
    address public isabelle = makeAddr("isabelle");
    address public james = makeAddr("james");

    address public RNO1 = makeAddr("RNO1");
    address public RNO2 = makeAddr("RNO2");
    address public RNO3 = makeAddr("RNO3");
    address public RNO4 = makeAddr("RNO4");
    address public RNO5 = makeAddr("RNO5");
    address public RNO6 = makeAddr("RNO6");
    address public RNO7 = makeAddr("RNO7");

    modifier fuzzedAddress(address addr) virtual {
        vm.assume(fuzzedAddressMapping[addr] == false);
        _;
    }

    modifier assumeEOA(address addr) {
        assumePayable(addr);
        assumeNotPrecompile(addr);
        vm.assume(addr.code.length == 0);
        vm.assume(addr != ADDRESS_ZERO);
        vm.assume(addr != ADDRESS_ONE);
        vm.assume(addr != 0x000000000000000000636F6e736F6c652e6c6f67); // console address
        _;
    }

    function setUp() public virtual {
        _deployContracts();
        _skipDefaultFuzzAddresses();
    }

    function _skipDefaultFuzzAddresses() internal {
        fuzzedAddressMapping[ADDRESS_CHEATS] = true;
        fuzzedAddressMapping[ADDRESS_ZERO] = true;
        fuzzedAddressMapping[ADDRESS_ONE] = true;
        fuzzedAddressMapping[address(accessManager)] = true;
        fuzzedAddressMapping[address(beacon)] = true;
        fuzzedAddressMapping[address(pufferProtocol)] = true;
        fuzzedAddressMapping[address(validatorTicket)] = true;
    }

    function _deployContracts() public {
        PufferProtocolDeployment memory pufferDeployment;
        BridgingDeployment memory bridgingDeployment;

        (pufferDeployment, bridgingDeployment) = new DeployEverything().run(PAYMASTER);

        pufferProtocol = PufferProtocol(payable(pufferDeployment.pufferProtocol));
        accessManager = AccessManager(pufferDeployment.accessManager);
        timelock = pufferDeployment.timelock;
        beacon = UpgradeableBeacon(pufferDeployment.beacon);
        pufferModuleManager = PufferModuleManager(payable(pufferDeployment.moduleManager));
        validatorTicket = ValidatorTicket(pufferDeployment.validatorTicket);
        pufferOracle = PufferOracleV2(pufferDeployment.pufferOracle);
        operationsCoordinator = OperationsCoordinator(payable(pufferDeployment.operationsCoordinator));
        validatorTicketPricer = ValidatorTicketPricer(pufferDeployment.validatorTicketPricer);
        avsContractsRegistry = AVSContractsRegistry(payable(pufferDeployment.aVSContractsRegistry));
        restakingOperatorController = RestakingOperatorController(payable(pufferDeployment.restakingOperatorController));
        // xpufETH = xPufETH(payable(bridgingDeployment.xPufETH));
        // lockBox = XERC20Lockbox(payable(bridgingDeployment.xPufETHLockBox));
        l1RewardManager = L1RewardManager(payable(bridgingDeployment.l1RewardManager));
        l2RewardManager = L2RewardManager(payable(bridgingDeployment.l2RewardManager));
        // connext = ConnextMock(payable(bridgingDeployment.connext));
        revenueDepositor = PufferRevenueDepositor(payable(pufferDeployment.revenueDepositor));
        // pufETHOFT = pufETH(payable(bridgingDeployment.pufETHOFT));
        // pufETHOFTAdapter = pufETHAdapter(payable(bridgingDeployment.pufETHOFTAdapter));
        layerzeroL1Endpoint = bridgingDeployment.layerzeroL1Endpoint;
        layerzeroL2Endpoint = bridgingDeployment.layerzeroL2Endpoint;

        // pufETH dependencies
        pufferVault = PufferVaultV5(payable(pufferDeployment.pufferVault));
        pufferDepositor = PufferDepositor(payable(pufferDeployment.pufferDepositor));
        stETH = stETHMock(payable(pufferDeployment.stETH));
        weth = IWETH(payable(pufferDeployment.weth));

        _upgradePufferVaultToMainnet();

        vm.label(address(pufferVault), "PufferVault");
        vm.label(address(pufferDepositor), "PufferDepositor");
        vm.label(address(pufferProtocol), "PufferProtocol");

        assertEq(
            blockhash(block.number),
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            "bad blockhash"
        );
    }

    function _upgradePufferVaultToMainnet() internal {
        // When we run any script in the test environment `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` is the msg.sender
        // That means that the _deployer in scripts is that address
        // Because of that, we grant it `upgrader`, so that it can run the upgrade script successfully
        vm.startPrank(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        accessManager.grantRole(1, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 0);

        uint64 protocolRoleId = 12345;
        accessManager.grantRole(protocolRoleId, address(pufferProtocol), 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PufferVaultV5.transferETH.selector;
        accessManager.setTargetFunctionRole(address(pufferVault), selectors, protocolRoleId);

        vm.stopPrank();

        _depositLiquidityToPufferVault();
    }

    function _depositLiquidityToPufferVault() internal {
        // DEPOSIT 1k ETH to the pool so that we have enough liquidity for provisioning
        vm.deal(LIQUIDITY_PROVIDER, 1000 ether);

        vm.startPrank(LIQUIDITY_PROVIDER);
        pufferVault.depositETH{ value: 1000 ether }(LIQUIDITY_PROVIDER);
        vm.stopPrank();
    }

    // Modified from https://github.com/Vectorized/solady/blob/2ced0d8382fd0289932010517d66efb28b07c3ce/test/ERC20.t.sol
    function _signPermit(_TestTemps memory t, bytes32 domainSeparator) internal pure returns (Permit memory p) {
        bytes32 innerHash = keccak256(abi.encode(_PERMIT_TYPEHASH, t.owner, t.to, t.amount, t.nonce, t.deadline));
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (t.v, t.r, t.s) = vm.sign(t.privateKey, outerHash);

        return Permit({ deadline: t.deadline, amount: t.amount, v: t.v, r: t.r, s: t.s });
    }

    function _testTemps(string memory seed, address to, uint256 amount, uint256 deadline)
        internal
        returns (_TestTemps memory t)
    {
        (t.owner, t.privateKey) = makeAddrAndKey(seed);
        t.to = to;
        t.amount = amount;
        t.deadline = deadline;
    }
}
