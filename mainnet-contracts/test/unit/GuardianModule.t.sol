// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IGuardianModule, PublicIdentity, GuardianSessionProof } from "../../src/interface/IGuardianModule.sol";
import { Unauthorized } from "../../src/Errors.sol";
import { SessionRegistryMock } from "../mocks/SessionRegistryMock.sol";
import { ALGO_ID_ES256K } from "@automata-network/automata-tee-workload-measurement/types/Constants.sol";
import { LibKey } from "@automata-network/automata-tee-workload-measurement/lib/LibKey.sol";

contract GuardianModuleTest is UnitTestHelper {
    uint256 public newSKEnclave;
    bytes public newEnclavePubKey;

    uint256 public newSKGuardian;
    address public newGuardian;
    bytes public newGuardianPubKey;

    PublicIdentity public newGuardianOwnerPublicIdentity;
    PublicIdentity public newGuardianSessionPublicIdentity;

    bytes32 public newGuardianSessionId = keccak256("newGuardianSessionId");

    function setUp() public override {
        // Just call the parent setUp()
        super.setUp();
        _skipDefaultFuzzAddresses();

        newSKEnclave = 40280701971156975094650330025087207427871411154031414620449944599045365691365;
        newEnclavePubKey =
            hex"04f6a0b4231ab4442dff42aeeb7a0f761d0591cd10f6ef793b545a78130955e485ce17a19dd12916bfc7b5230e8e16ac14050069ed7609f926346912b2a899df21";

        newSKGuardian = 62446650044403031109669988213557076707788335704243384097041391592912982163892;
        newGuardianPubKey =
            hex"0410a8e13cb502346e709da19444ffa7584377fd6c68f8a8c3689edef46deac332523d15524394b64c932added00b6a0f9452b2c5cf8fee12e176a10a1dabbd7ba";
        newGuardian = vm.addr(newSKGuardian);

        newGuardianOwnerPublicIdentity = PublicIdentity({ typeId: ALGO_ID_ES256K, key: newGuardianPubKey });
        newGuardianSessionPublicIdentity = PublicIdentity({ typeId: ALGO_ID_ES256K, key: newEnclavePubKey });
    }

    function test_setup() public view {
        assertEq(guardianModule.getEjectionThreshold(), 31.75 ether, "initial value ejection threshold (31.75)");
        assertEq(guardianModule.getThreshold(), 1, "initial value threshold (1)");
    }

    function test_rave() public {
        _deployContractAndSetupGuardians();
    }

    function test_set_threshold_to_0_reverts() public {
        vm.startPrank(DAO);
        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.InvalidThreshold.selector, 0));
        guardianModule.setThreshold(0);
    }

    function test_set_threshold_to_50_reverts() public {
        // 50 is more than the number of guardians
        vm.startPrank(DAO);
        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.InvalidThreshold.selector, 50));
        guardianModule.setThreshold(50);
    }

    function test_addGuardian(address guardian) public assumeEOA(guardian) {
        vm.startPrank(DAO);

        // Must not be a guardian already
        vm.assume(!guardianModule.isGuardian(guardian));

        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.GuardianAdded(guardian);
        guardianModule.addGuardian(guardian);
    }

    function test_removeGuardian(address guardian) public {
        test_addGuardian(guardian);

        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.GuardianRemoved(guardian);
        guardianModule.removeGuardian(guardian);
    }

    function test_remove_guardian_below_threshold() public {
        // Our test env has 3 guardians and threshold 1

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.ThresholdChanged(1, 3);
        guardianModule.setThreshold(3);
        assertEq(guardianModule.getThreshold(), 3, "guardians threshold");

        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.InvalidThreshold.selector, 3));
        guardianModule.removeGuardian(guardian1);
    }

    function test_splitFunds() public {
        vm.deal(address(guardianModule), 1 ether);

        guardianModule.splitGuardianFunds();

        assertEq(guardian1.balance, guardian2.balance, "guardian balances");
        assertEq(guardian1.balance, guardian3.balance, "guardian balances");
    }

    function test_set_threshold() public {
        vm.startPrank(DAO);

        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.ThresholdChanged(1, 2);
        guardianModule.setThreshold(2);
    }

    function test_set_threshold_reverts() public {
        vm.startPrank(DAO);

        // We have 3 guardians, try setting threshold to 5
        vm.expectRevert();
        guardianModule.setThreshold(5);
    }

    // Invalid signature reverts with unauthorized
    function test_validateSkipProvisioning_reverts() public {
        (, uint256 bobSK) = makeAddrAndKey("bob");
        bytes[] memory guardianSignatures = new bytes[](3);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobSK, bytes32("whatever"));
        guardianSignatures[0] = abi.encodePacked(r, s, v);
        vm.expectRevert(Unauthorized.selector);
        guardianModule.validateSkipProvisioning(PUFFER_MODULE_0, 0, guardianSignatures);
    }

    function test_split_funds_rounding() external {
        vm.deal(address(guardianModule), 2); // 2 wei, but 3 guardians
        // shouldn't revert, but due to rounding down, they will not receive any eth
        guardianModule.splitGuardianFunds();

        assertEq(guardian1.balance, 0);
        assertEq(guardian2.balance, 0);
        assertEq(guardian3.balance, 0);

        vm.deal(address(guardianModule), 32); // 32 wei on 3 guardians = 10 each, the rest stays in the module
        guardianModule.splitGuardianFunds();

        assertEq(guardian1.balance, 10);
        assertEq(guardian2.balance, 10);
        assertEq(guardian3.balance, 10);
        assertEq(address(guardianModule).balance, 2);
    }

    function test_setAllowedWorkload() public {
        vm.startPrank(DAO);

        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.WorkloadNotAllowed.selector));
        guardianModule.setAllowedWorkload(bytes32(0), true);

        bytes32 workloadId = keccak256("test_workload");

        // Initially workload should not be allowed
        assertFalse(guardianModule.isWorkloadAllowed(workloadId), "workload should not be allowed initially");

        // Set workload as allowed
        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.WorkloadAllowanceChanged(workloadId, true);
        guardianModule.setAllowedWorkload(workloadId, true);

        // Verify workload is now allowed
        assertTrue(guardianModule.isWorkloadAllowed(workloadId), "workload should be allowed");

        // Set workload as not allowed
        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.WorkloadAllowanceChanged(workloadId, false);
        guardianModule.setAllowedWorkload(workloadId, false);

        // Verify workload is not allowed anymore
        assertFalse(guardianModule.isWorkloadAllowed(workloadId), "workload should not be allowed");

        vm.stopPrank();
    }

    function test_rotateGuardianKey_invalid_algorithm() public {
        newGuardianOwnerPublicIdentity.typeId = 0; // invalid algorithm

        vm.expectRevert(IGuardianModule.InvalidECDSAPubKey.selector);
        guardianModule.rotateGuardianKey(
            0,
            abi.encodePacked(newGuardianPubKey, bytes1(0x00)), // invalid length
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_invalid_owner_key_length() public {
        newGuardianOwnerPublicIdentity.key = abi.encodePacked(newGuardianOwnerPublicIdentity.key, bytes1(0x00)); // invalid length

        vm.expectRevert(IGuardianModule.InvalidECDSAPubKey.selector);
        guardianModule.rotateGuardianKey(
            0,
            abi.encodePacked(newGuardianPubKey, bytes1(0x00)), // invalid length
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_from_non_guardian_reverts() public {
        vm.expectRevert(Unauthorized.selector);
        guardianModule.rotateGuardianKey(
            0,
            new bytes(65),
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_invalid_pubkey_length() public {
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        vm.expectRevert(IGuardianModule.InvalidECDSAPubKey.selector);
        guardianModule.rotateGuardianKey(
            0,
            abi.encodePacked(newGuardianPubKey, bytes1(0x00)), // invalid length
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_stale_evidence() public {
        vm.roll(block.number + FRESHNESS_BLOCKS + 1); // move forward in time to make the proof stale
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        vm.expectRevert(IGuardianModule.StaleEvidence.selector);
        guardianModule.rotateGuardianKey(
            0,
            newGuardianPubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_invalid_signature() public {
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        vm.expectRevert(IGuardianModule.InvalidSignature.selector);
        guardianModule.rotateGuardianKey(
            0,
            newGuardianPubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_invalid_owner_fingerprint() public {
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        bytes32 signedMessageHash =
            keccak256(abi.encode("ROTATE_GUARDIAN_KEY", address(guardianModule), block.chainid, 0, newEnclavePubKey));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newSKEnclave, signedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        sessionRegistryMock.setSessionOwner(
            newGuardianSessionId, LibKey.computeKeyFingerprint(newGuardianOwnerPublicIdentity)
        );

        vm.expectRevert(IGuardianModule.InvalidECDSAPubKey.selector);
        guardianModule.rotateGuardianKey(
            0,
            newEnclavePubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: guardian1OwnerPublicIdentity, // invalid owner key (not matching the one used to sign)
                signature: signature
            })
        );
    }

    function test_rotateGuardianKey_invalid_workload_not_allowed() public {
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        bytes32 signedMessageHash =
            keccak256(abi.encode("ROTATE_GUARDIAN_KEY", address(guardianModule), block.chainid, 0, newEnclavePubKey));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newSKEnclave, signedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        sessionRegistryMock.setSessionOwner(
            newGuardianSessionId, LibKey.computeKeyFingerprint(newGuardianOwnerPublicIdentity)
        );

        vm.expectRevert(IGuardianModule.WorkloadNotAllowed.selector);
        guardianModule.rotateGuardianKey(
            0,
            newEnclavePubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: signature
            })
        );
    }

    function test_rotateGuardianKey_success() public {
        bytes32 workloadId = keccak256("allowed_workload");
        vm.startPrank(DAO);
        guardianModule.addGuardian(newGuardian);
        guardianModule.setAllowedWorkload(workloadId, true);
        vm.stopPrank();

        bytes32 signedMessageHash =
            keccak256(abi.encode("ROTATE_GUARDIAN_KEY", address(guardianModule), block.chainid, 0, newEnclavePubKey));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newSKEnclave, signedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        sessionRegistryMock.setSessionOwner(
            newGuardianSessionId, LibKey.computeKeyFingerprint(newGuardianOwnerPublicIdentity)
        );

        sessionRegistryMock.setSessionWorkload(newGuardianSessionId, workloadId);

        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.RotatedGuardianKey(newGuardian, vm.addr(newSKEnclave), newEnclavePubKey);
        guardianModule.rotateGuardianKey(
            0,
            newEnclavePubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: signature
            })
        );

        assertEq(guardianModule.getGuardiansEnclaveAddress(newGuardian), vm.addr(newSKEnclave), "bad enclave address");
    }
}
