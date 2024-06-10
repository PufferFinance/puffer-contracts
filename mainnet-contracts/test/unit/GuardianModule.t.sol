// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { RaveEvidence } from "../../src/struct/RaveEvidence.sol";
import { RaveEvidence } from "../../src/struct/RaveEvidence.sol";
import { IGuardianModule } from "../../src/interface/IGuardianModule.sol";
import { Guardian2RaveEvidence } from "../helpers/GuardiansRaveEvidence.sol";
import { Unauthorized } from "../../src/Errors.sol";

contract GuardianModuleTest is UnitTestHelper {
    function setUp() public override {
        // Just call the parent setUp()
        super.setUp();
        _skipDefaultFuzzAddresses();
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

    function test_rotateGuardianKey_from_non_guardian_reverts() public {
        RaveEvidence memory evidence;
        vm.expectRevert(Unauthorized.selector);
        guardianModule.rotateGuardianKey(0, new bytes(55), evidence);
    }

    function test_rotateGuardianKey_to_invalid_pubKey_everts() public {
        RaveEvidence memory evidence;

        vm.startPrank(guardian1);

        vm.expectRevert(IGuardianModule.InvalidECDSAPubKey.selector);
        guardianModule.rotateGuardianKey(0, new bytes(55), evidence);
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

    function test_remove_guardian_bellow_threshold() public {
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

    function test_rotateGuardianKey_with_invalid_rave_reverts() public {
        Guardian2RaveEvidence guardian2Rave = new Guardian2RaveEvidence();

        vm.startPrank(guardian1);

        RaveEvidence memory rave = RaveEvidence({
            report: guardian2Rave.report(),
            signature: guardian2Rave.sig(),
            leafX509CertDigest: keccak256(guardian2Rave.signingCert())
        });

        vm.expectRevert(IGuardianModule.InvalidRAVE.selector);
        guardianModule.rotateGuardianKey(0, guardian3EnclavePubKey, rave);
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
}
