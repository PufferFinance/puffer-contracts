// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { PermissionedModule } from "../../src/PermissionedModule.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { NonRestakingWithdrawalCredentials } from "../../src/NonRestakingWithdrawalCredentials.sol";
import { IEigenPodTypes } from "src/interface/Eigenlayer-Slashing/IEigenPod.sol";
import { IDelegationManager } from "src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IRewardsCoordinator } from "src/interface/Eigenlayer-Slashing/IRewardsCoordinator.sol";
import { IBeaconDepositContract } from "src/interface/IBeaconDepositContract.sol";
import { IPufferProtocol } from "src/interface/IPufferProtocol.sol";
import { EigenPodManagerMock } from "../mocks/EigenPodManagerMock.sol";
import { DelegationManagerMock } from "../mocks/DelegationManagerMock.sol";
import { RewardsCoordinatorMock } from "../mocks/RewardsCoordinatorMock.sol";
import { BeaconMock } from "../mocks/BeaconMock.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { Unauthorized } from "../../src/Errors.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title PermissionedModuleStandaloneTest
 * @notice Standalone tests for PermissionedModule that don't require full deployment infrastructure
 * @dev Tests the triggerNonRestakedValidatorWithdrawals functionality and related flows
 */
contract PermissionedModuleStandaloneTest is Test {
    bytes32 public constant MODULE_NAME = bytes32("TEST_PERM_MODULE");
    uint256 constant EXIT_FEE = 0.0001 ether;

    PermissionedModule public permissionedModule;
    address public eigenPodManagerMock;
    address public delegationManagerMock;
    address public rewardsCoordinatorMock;
    address public beaconDepositMock;
    AccessManager public accessManager;

    // Mock addresses
    address public pufferProtocolAddr;
    address public pufferModuleManagerAddr;
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        pufferProtocolAddr = makeAddr("pufferProtocol");
        pufferModuleManagerAddr = makeAddr("pufferModuleManager");

        vm.deal(owner, 1000 ether);
        vm.deal(pufferModuleManagerAddr, 1000 ether);

        // Deploy AccessManager for NonRestakingWithdrawalCredentials
        accessManager = new AccessManager(owner);

        // Deploy mocks
        eigenPodManagerMock = address(new EigenPodManagerMock());
        delegationManagerMock = address(new DelegationManagerMock());
        rewardsCoordinatorMock = address(new RewardsCoordinatorMock());
        beaconDepositMock = address(new BeaconMock());

        // Deploy implementation
        PermissionedModule impl = new PermissionedModule(
            IPufferProtocol(pufferProtocolAddr),
            eigenPodManagerMock,
            IDelegationManager(delegationManagerMock),
            PufferModuleManager(payable(pufferModuleManagerAddr)),
            IRewardsCoordinator(rewardsCoordinatorMock),
            IBeaconDepositContract(beaconDepositMock)
        );

        // Deploy beacon
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), owner);

        // Deploy proxy - use accessManager as the initialAuthority
        bytes memory initData =
            abi.encodeWithSelector(PermissionedModule.initialize.selector, MODULE_NAME, address(accessManager));
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        permissionedModule = PermissionedModule(payable(address(proxy)));

        // Grant permissions for NonRestakingWithdrawalCredentials.requestWithdrawal
        // In production, this would be restricted to the PermissionedModule only
        // For testing, we set it to PUBLIC_ROLE so any authorized caller can test the flow
        address nrwc = permissionedModule.getNonRestakingWithdrawalCredentialsContract();
        bytes4 requestWithdrawalSelector = NonRestakingWithdrawalCredentials.requestWithdrawal.selector;

        vm.startPrank(owner);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = requestWithdrawalSelector;
        accessManager.setTargetFunctionRole(nrwc, selectors, accessManager.PUBLIC_ROLE());
        vm.stopPrank();

        // Mock the EIP-7002 withdrawal request precompile
        _mockWithdrawalRequestPrecompile();
    }

    function _mockWithdrawalRequestPrecompile() internal {
        // Mock the withdrawal request address to return a fee and accept calls
        address WITHDRAWAL_REQUEST_ADDRESS = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

        // Mock getWithdrawalRequestFee - returns fee in bytes32 format
        vm.mockCall(WITHDRAWAL_REQUEST_ADDRESS, bytes(""), abi.encode(EXIT_FEE));
    }

    // ============ Module Initialization Tests ============

    function test_moduleInitialization() public view {
        assertEq(permissionedModule.NAME(), MODULE_NAME, "Module name mismatch");
        assertTrue(permissionedModule.getEigenPod() != address(0), "EigenPod not created");
        assertTrue(
            permissionedModule.getNonRestakingWithdrawalCredentialsContract() != address(0),
            "NonRestakingWithdrawalCredentials not created"
        );
    }

    function test_withdrawalCredentialsFormat() public view {
        // Restaking credentials should start with 0x01 (EigenPod)
        bytes memory restakingCreds = permissionedModule.getRestakingWithdrawalCredentials();
        assertEq(restakingCreds[0], bytes1(0x01), "Restaking credentials should start with 0x01");
        assertEq(restakingCreds.length, 32, "Restaking credentials should be 32 bytes");

        // Non-restaking credentials should start with 0x02 (compounding)
        bytes memory nonRestakingCreds = permissionedModule.getNonRestakingWithdrawalCredentials();
        assertEq(nonRestakingCreds[0], bytes1(0x02), "Non-restaking credentials should start with 0x02");
        assertEq(nonRestakingCreds.length, 32, "Non-restaking credentials should be 32 bytes");
    }

    function test_immutableAddresses() public view {
        assertEq(address(permissionedModule.PUFFER_PROTOCOL()), pufferProtocolAddr, "PUFFER_PROTOCOL mismatch");
        assertEq(
            address(permissionedModule.PUFFER_MODULE_MANAGER()),
            pufferModuleManagerAddr,
            "PUFFER_MODULE_MANAGER mismatch"
        );
        assertEq(address(permissionedModule.EIGEN_POD_MANAGER()), eigenPodManagerMock, "EIGEN_POD_MANAGER mismatch");
        assertEq(
            address(permissionedModule.EIGEN_DELEGATION_MANAGER()),
            delegationManagerMock,
            "EIGEN_DELEGATION_MANAGER mismatch"
        );
    }

    // ============ triggerNonRestakedValidatorWithdrawals Tests ============

    function test_triggerNonRestakedValidatorWithdrawals_fullExit() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({
            pubkey: _generatePubkey(1),
            amountGwei: 0 // Full exit
         });

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: EXIT_FEE }(requests);
    }

    function test_triggerNonRestakedValidatorWithdrawals_partialWithdrawal() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({
            pubkey: _generatePubkey(1),
            amountGwei: 1_000_000_000 // 1 ETH partial withdrawal
         });

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: EXIT_FEE }(requests);
    }

    function test_triggerNonRestakedValidatorWithdrawals_multipleRequests() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](3);

        // Mix of full exits and partial withdrawals
        requests[0] = IEigenPodTypes.WithdrawalRequest({
            pubkey: _generatePubkey(1),
            amountGwei: 0 // Full exit
         });
        requests[1] = IEigenPodTypes.WithdrawalRequest({
            pubkey: _generatePubkey(2),
            amountGwei: 5_000_000_000 // 5 ETH partial
         });
        requests[2] = IEigenPodTypes.WithdrawalRequest({
            pubkey: _generatePubkey(3),
            amountGwei: 10_000_000_000 // 10 ETH partial
         });

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: 3 * EXIT_FEE }(requests);
    }

    function test_triggerNonRestakedValidatorWithdrawals_maxUint64Amount() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);

        // Max uint64 amount in gwei
        requests[0] = IEigenPodTypes.WithdrawalRequest({ pubkey: _generatePubkey(1), amountGwei: type(uint64).max });

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: EXIT_FEE }(requests);
    }

    // ============ Access Control Tests ============

    function test_triggerNonRestakedValidatorWithdrawals_unauthorized() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({ pubkey: _generatePubkey(1), amountGwei: 0 });

        address randomUser = makeAddr("randomUser");
        vm.deal(randomUser, 1 ether);

        vm.prank(randomUser);
        vm.expectRevert(Unauthorized.selector);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: EXIT_FEE }(requests);
    }

    function test_triggerNonRestakedValidatorWithdrawals_fromOwner_unauthorized() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({ pubkey: _generatePubkey(1), amountGwei: 0 });

        // Even owner cannot call directly - only pufferModuleManager
        vm.prank(owner);
        vm.expectRevert(Unauthorized.selector);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: EXIT_FEE }(requests);
    }

    function test_withdrawNonRestakedETH_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.prank(randomUser);
        vm.expectRevert(Unauthorized.selector);
        permissionedModule.withdrawNonRestakedETH();
    }

    // ============ Fuzz Tests ============

    function testFuzz_triggerNonRestakedValidatorWithdrawals_partialAmount(uint64 amountGwei) public {
        vm.assume(amountGwei > 0); // Skip zero as that's a full exit

        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({ pubkey: _generatePubkey(1), amountGwei: amountGwei });

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: EXIT_FEE }(requests);
    }

    function testFuzz_triggerNonRestakedValidatorWithdrawals_multipleValidators(uint8 numValidators) public {
        numValidators = uint8(bound(numValidators, 1, 20));

        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](numValidators);

        for (uint256 i = 0; i < numValidators; i++) {
            requests[i] = IEigenPodTypes.WithdrawalRequest({
                pubkey: _generatePubkey(i),
                amountGwei: uint64(i * 1_000_000_000) // 0, 1 ETH, 2 ETH, etc.
             });
        }

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: uint256(numValidators) * EXIT_FEE }(requests);
    }

    function testFuzz_triggerNonRestakedValidatorWithdrawals_anyAmount(uint64 amount1, uint64 amount2, uint64 amount3)
        public
    {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](3);

        requests[0] = IEigenPodTypes.WithdrawalRequest({ pubkey: _generatePubkey(1), amountGwei: amount1 });
        requests[1] = IEigenPodTypes.WithdrawalRequest({ pubkey: _generatePubkey(2), amountGwei: amount2 });
        requests[2] = IEigenPodTypes.WithdrawalRequest({ pubkey: _generatePubkey(3), amountGwei: amount3 });

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: 3 * EXIT_FEE }(requests);
    }

    // ============ Edge Cases ============

    function test_triggerNonRestakedValidatorWithdrawals_singleGwei() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({
            pubkey: _generatePubkey(1),
            amountGwei: 1 // Minimum possible partial withdrawal (1 gwei)
         });

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: EXIT_FEE }(requests);
    }

    function test_triggerNonRestakedValidatorWithdrawals_32EthInGwei() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({
            pubkey: _generatePubkey(1),
            amountGwei: 32_000_000_000 // 32 ETH in gwei
         });

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: EXIT_FEE }(requests);
    }

    function test_triggerNonRestakedValidatorWithdrawals_2048EthInGwei() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](1);
        requests[0] = IEigenPodTypes.WithdrawalRequest({
            pubkey: _generatePubkey(1),
            amountGwei: 2048_000_000_000 // 2048 ETH in gwei (Pectra MaxEB)
         });

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: EXIT_FEE }(requests);
    }

    function test_triggerNonRestakedValidatorWithdrawals_emptyArray() public {
        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](0);

        // Should not revert at module level - validation is in PufferModuleManager
        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerNonRestakedValidatorWithdrawals{ value: 0 }(requests);
    }

    // ============ NonRestakingWithdrawalCredentials Tests ============

    function test_nonRestakingWithdrawalCredentials_withdrawETH() public {
        address nrwc = permissionedModule.getNonRestakingWithdrawalCredentialsContract();

        // Send some ETH to simulate beacon chain withdrawal
        vm.deal(nrwc, 10 ether);

        uint256 moduleBalanceBefore = address(permissionedModule).balance;

        // Call withdrawNonRestakedETH
        vm.prank(pufferModuleManagerAddr);
        permissionedModule.withdrawNonRestakedETH();

        assertEq(address(permissionedModule).balance, moduleBalanceBefore + 10 ether, "ETH should be withdrawn");
        assertEq(nrwc.balance, 0, "NRWC balance should be zero");
    }

    function test_nonRestakingWithdrawalCredentials_withdrawETH_unauthorized() public {
        // Get the NRWC address first (separate from the expectRevert)
        address nrwc = permissionedModule.getNonRestakingWithdrawalCredentialsContract();

        // Direct call should fail - only PermissionedModule can call
        vm.expectRevert(Unauthorized.selector);
        NonRestakingWithdrawalCredentials(payable(nrwc)).withdrawETH();
    }

    function test_nonRestakingWithdrawalCredentials_receiveETH() public {
        address nrwc = permissionedModule.getNonRestakingWithdrawalCredentialsContract();

        // NRWC should be able to receive ETH (from beacon chain withdrawals)
        vm.deal(address(this), 10 ether);
        (bool success,) = nrwc.call{ value: 10 ether }("");
        assertTrue(success, "NRWC should receive ETH");
        assertEq(nrwc.balance, 10 ether, "NRWC balance should be 10 ether");
    }

    function testFuzz_nonRestakingWithdrawalCredentials_withdrawETH(uint256 amount) public {
        amount = bound(amount, 0, 1000 ether);

        address nrwc = permissionedModule.getNonRestakingWithdrawalCredentialsContract();
        vm.deal(nrwc, amount);

        uint256 moduleBalanceBefore = address(permissionedModule).balance;

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.withdrawNonRestakedETH();

        assertEq(address(permissionedModule).balance, moduleBalanceBefore + amount, "ETH should be withdrawn");
        assertEq(nrwc.balance, 0, "NRWC balance should be zero");
    }

    // ============ triggerRestakedValidatorsExit Tests ============

    function test_triggerRestakedValidatorsExit() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = _generatePubkey(1);

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerRestakedValidatorsExit{ value: EXIT_FEE }(pubkeys);
    }

    function test_triggerRestakedValidatorsExit_multiplePubkeys() public {
        bytes[] memory pubkeys = new bytes[](3);
        pubkeys[0] = _generatePubkey(1);
        pubkeys[1] = _generatePubkey(2);
        pubkeys[2] = _generatePubkey(3);

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerRestakedValidatorsExit{ value: 3 * EXIT_FEE }(pubkeys);
    }

    function test_triggerRestakedValidatorsExit_unauthorized() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = _generatePubkey(1);

        address randomUser = makeAddr("randomUser");
        vm.deal(randomUser, 1 ether);

        vm.prank(randomUser);
        vm.expectRevert(Unauthorized.selector);
        permissionedModule.triggerRestakedValidatorsExit{ value: EXIT_FEE }(pubkeys);
    }

    function testFuzz_triggerRestakedValidatorsExit(uint8 numPubkeys) public {
        numPubkeys = uint8(bound(numPubkeys, 1, 20));

        bytes[] memory pubkeys = new bytes[](numPubkeys);
        for (uint256 i = 0; i < numPubkeys; i++) {
            pubkeys[i] = _generatePubkey(i);
        }

        vm.prank(pufferModuleManagerAddr);
        permissionedModule.triggerRestakedValidatorsExit{ value: uint256(numPubkeys) * EXIT_FEE }(pubkeys);
    }

    // ============ Module can receive ETH ============

    function test_moduleCanReceiveETH() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(permissionedModule).call{ value: 10 ether }("");
        assertTrue(success, "Module should receive ETH");
        assertEq(address(permissionedModule).balance, 10 ether, "Module balance should be 10 ether");
    }

    // ============ Helper Functions ============

    function _generatePubkey(uint256 seed) internal pure returns (bytes memory) {
        bytes memory pubkey = new bytes(48);
        for (uint256 i = 0; i < 48; i++) {
            pubkey[i] = bytes1(uint8(uint256(keccak256(abi.encode(seed, i))) % 256));
        }
        return pubkey;
    }
}
