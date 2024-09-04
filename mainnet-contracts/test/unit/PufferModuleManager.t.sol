// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { PufferModule } from "../../src/PufferModule.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { AVSContractsRegistry } from "../../src/AVSContractsRegistry.sol";
import { IPufferModuleManager } from "../../src/interface/IPufferModuleManager.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Merkle } from "murky/Merkle.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";
import { Unauthorized } from "../../src/Errors.sol";
import { ROLE_ID_OPERATIONS_PAYMASTER } from "../../script/Roles.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { IRestakingOperator } from "../../src/interface/IRestakingOperator.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract PufferModuleUpgrade {
    function getMagicValue() external pure returns (uint256) {
        return 1337;
    }
}

contract PufferModuleManagerTest is UnitTestHelper {
    Merkle rewardsMerkleProof;
    bytes32[] rewardsMerkleProofData;

    bytes32 CRAZY_GAINS = bytes32("CRAZY_GAINS");

    function setUp() public override {
        super.setUp();

        vm.deal(address(this), 1000 ether);

        vm.startPrank(timelock);
        accessManager.grantRole(ROLE_ID_OPERATIONS_PAYMASTER, address(this), 0);
        vm.stopPrank();

        _skipDefaultFuzzAddresses();
    }

    function test_beaconUpgrade() public {
        address moduleBeacon = pufferModuleManager.PUFFER_MODULE_BEACON();

        vm.startPrank(DAO);
        pufferProtocol.createPufferModule(bytes32("DEGEN"));
        vm.stopPrank();

        // No restaking is a custom default module (non beacon upgradeable)
        (bool success,) = pufferProtocol.getModuleAddress(bytes32("DEGEN")).call(
            abi.encodeCall(PufferModuleUpgrade.getMagicValue, ())
        );

        assertTrue(!success, "should not succeed");

        PufferModuleUpgrade upgrade = new PufferModuleUpgrade();

        vm.startPrank(timelock);
        accessManager.execute(moduleBeacon, abi.encodeCall(UpgradeableBeacon.upgradeTo, address(upgrade)));
        vm.stopPrank();

        (bool s, bytes memory data) = pufferProtocol.getModuleAddress(bytes32("DEGEN")).call(
            abi.encodeCall(PufferModuleUpgrade.getMagicValue, ())
        );
        assertTrue(s, "should succeed");
        assertEq(abi.decode(data, (uint256)), 1337, "got the number");
    }

    function test_createPufferModule(bytes32 moduleName) public {
        address module = _createPufferModule(moduleName);
        assertEq(PufferModule(payable(module)).NAME(), moduleName, "bad name");
    }

    function test_pufferModuleAuthorization(bytes32 moduleName) public {
        address module = _createPufferModule(moduleName);

        vm.expectRevert(Unauthorized.selector);
        PufferModule(payable(module)).callStake("", "", "");

        vm.expectRevert(Unauthorized.selector);
        PufferModule(payable(module)).call(address(0), 0, "");
    }

    function test_donation(bytes32 moduleName) public {
        address module = _createPufferModule(moduleName);
        (bool s,) = address(module).call{ value: 5 ether }("");
        assertTrue(s);
    }

    function test_callDelegateTo(
        bytes32 moduleName,
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signatureWithExpiry,
        bytes32 approverSalt
    ) public {
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));

        address module = _createPufferModule(moduleName);
        vm.startPrank(DAO);

        vm.expectRevert(Unauthorized.selector);
        PufferModule(payable(module)).callDelegateTo(operator, signatureWithExpiry, approverSalt);

        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.PufferModuleDelegated(moduleName, operator);

        pufferModuleManager.callDelegateTo(moduleName, operator, signatureWithExpiry, approverSalt);

        vm.stopPrank();
    }

    function test_callUndelegate(bytes32 moduleName) public {
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));

        address module = _createPufferModule(moduleName);
        vm.startPrank(DAO);

        vm.expectRevert(Unauthorized.selector);
        PufferModule(payable(module)).callUndelegate();

        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.PufferModuleUndelegated(moduleName);

        pufferModuleManager.callUndelegate(moduleName);

        vm.stopPrank();
    }

    function test_setClaimerForModule(bytes32 moduleName, address claimer) public {
        vm.assume(claimer != address(0));
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));
        address module = _createPufferModule(moduleName);

        vm.startPrank(DAO);

        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.ClaimerSet({ rewardsReceiver: address(module), claimer: claimer });
        pufferModuleManager.callSetClaimerFor(module, claimer);
    }

    function test_setClaimerForReOp(address claimer) public {
        vm.assume(claimer != address(0));

        vm.startPrank(DAO);
        IRestakingOperator operator = _createRestakingOperator();

        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.ClaimerSet({ rewardsReceiver: address(operator), claimer: claimer });
        pufferModuleManager.callSetClaimerFor(address(operator), claimer);
    }

    function test_setProofSubmitter(bytes32 moduleName, address proofSubmitter) public {
        vm.assume(proofSubmitter != address(0));
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));
        _createPufferModule(moduleName);

        vm.startPrank(DAO);

        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.ProofSubmitterSet(moduleName, proofSubmitter);
        pufferModuleManager.callSetProofSubmitter(moduleName, proofSubmitter);
    }

    function test_startCheckpoint(bytes32 moduleName) public {
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));

        vm.startPrank(DAO);

        address module = _createPufferModule(moduleName);
        address[] memory modules = new address[](1);
        modules[0] = module;

        vm.startPrank(DAO);

        pufferModuleManager.callStartCheckpoint(modules);
    }

    function testRevert_createPufferModuleForbiddenName() public {
        vm.startPrank(DAO);
        vm.expectRevert(IPufferModuleManager.ForbiddenModuleName.selector);
        pufferProtocol.createPufferModule(bytes32("NO_VALIDATORS"));

        vm.stopPrank();
    }

    function test_createPufferModuleUnauthrozied() public {
        vm.expectRevert(Unauthorized.selector);
        pufferModuleManager.createNewPufferModule(bytes32("random"));
    }

    function test_module_has_eigenPod(bytes32 moduleName) public {
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));
        address module = _createPufferModule(moduleName);

        assertTrue(PufferModule(payable(module)).getEigenPod() != address(0), "should have EigenPod");
    }

    function test_rewards_claiming_from_eigenlayer(bytes32 moduleName) public {
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));
        _createPufferModule(moduleName);

        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.WithdrawalsQueued(moduleName, 1 ether, bytes32("123"));
        pufferModuleManager.callQueueWithdrawals(moduleName, 1 ether);
    }

    // Sets the claimer for PufferModule & ReOp
    function test_set_claimer_for_avs_rewards(address claimer, bytes32 moduleName) public {
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));
        vm.assume(claimer != address(0));

        address createdModule = _createPufferModule(moduleName);

        vm.startPrank(DAO);
        IRestakingOperator operator = _createRestakingOperator();

        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.ClaimerSet(address(createdModule), claimer);
        pufferModuleManager.callSetClaimerFor(createdModule, claimer);

        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.ClaimerSet(address(operator), claimer);
        pufferModuleManager.callSetClaimerFor(address(operator), claimer);
    }

    function test_completeQueuedWithdrawals(bytes32 moduleName) public {
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));
        _createPufferModule(moduleName);

        IDelegationManager.Withdrawal[] memory withdrawals;
        IERC20[][] memory tokens;
        uint256[] memory middlewareTimesIndexes;
        bool[] memory receiveAsTokens;

        emit IPufferModuleManager.CompletedQueuedWithdrawals(moduleName, 0);
        pufferModuleManager.callCompleteQueuedWithdrawals(
            moduleName, withdrawals, tokens, middlewareTimesIndexes, receiveAsTokens
        );
    }

    function test_updateAVSRegistrationSignatureProof() public {
        (address signer, uint256 pk) = makeAddrAndKey("signer");

        vm.startPrank(DAO);

        IRestakingOperator operator = _createRestakingOperator();

        bytes32 salt = 0xdebc2c61283b511dc62175c508bc9c6ad8ca754ba918164e6a9b19765c98006d;
        bytes32 digestHash = keccak256(
            abi.encode("OPERATOR_AVS_REGISTRATION_TYPEHASH", address(operator), address(1234), salt, block.timestamp)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digestHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Unauthorized.selector);
        operator.updateSignatureProof(digestHash, signer);

        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.AVSRegistrationSignatureProofUpdated(address(operator), digestHash, signer);
        pufferModuleManager.updateAVSRegistrationSignatureProof(operator, digestHash, signer);

        assertTrue(
            SignatureChecker.isValidERC1271SignatureNow(address(operator), digestHash, signature), "signer proof"
        );

        bytes32 fakeDigestHash = keccak256(abi.encode(digestHash));

        assertFalse(
            SignatureChecker.isValidERC1271SignatureNow(address(operator), fakeDigestHash, signature), "signer proof"
        );

        vm.stopPrank();
    }

    function test_customExternalCall() public {
        vm.startPrank(DAO);
        IRestakingOperator operator = _createRestakingOperator();

        bytes memory customCalldata = abi.encodeCall(PufferModuleManagerTest.getMagicNumber, ());

        // Not allowlisted, revert
        vm.expectRevert();
        pufferModuleManager.customExternalCall(operator, address(this), customCalldata);

        // Generate allowlist cd
        bytes memory allowlistCalldata = abi.encodeWithSelector(
            AVSContractsRegistry.setAvsRegistryCoordinator.selector,
            address(this),
            PufferModuleManagerTest.getMagicNumber.selector,
            true
        );

        // Schedule adding the registry coordinator contract (this contract as a mock) to the allowlist
        // accessManager.schedule(address(avsContractsRegistry), allowlistCalldata, 0);

        // Advance the timestamp
        vm.warp(block.timestamp + 1 days + 1);
        // execute the allowlist calldata
        accessManager.execute(address(avsContractsRegistry), allowlistCalldata);

        // Now it works
        vm.expectEmit(true, true, true, true);
        emit IPufferModuleManager.CustomCallSucceeded({
            restakingOperator: address(operator),
            target: address(this),
            customCalldata: customCalldata,
            response: abi.encode(85858585)
        });
        pufferModuleManager.customExternalCall(
            operator, address(this), abi.encodeCall(PufferModuleManagerTest.getMagicNumber, ())
        );

        // Generate allowlist cd to remove the selector from the allowlist
        allowlistCalldata = abi.encodeWithSelector(
            AVSContractsRegistry.setAvsRegistryCoordinator.selector,
            address(this),
            PufferModuleManagerTest.getMagicNumber.selector,
            false
        );

        // Schedule adding the registry coordinator contract (this contract as a mock) to the allowlist
        // accessManager.schedule(address(avsContractsRegistry), allowlistCalldata, 0);

        // Advance the timestamp
        vm.warp(block.timestamp + 1 days + 1);
        // execute the allowlist calldata
        accessManager.execute(address(avsContractsRegistry), allowlistCalldata);

        // Not allowlisted, revert
        vm.expectRevert();
        pufferModuleManager.customExternalCall(operator, address(this), customCalldata);
        vm.stopPrank();
    }

    function _createPufferModule(bytes32 moduleName) internal returns (address module) {
        vm.assume(pufferProtocol.getModuleAddress(moduleName) == address(0));
        vm.assume(bytes32("NO_VALIDATORS") != moduleName);

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit Initializable.Initialized(1);
        module = pufferProtocol.createPufferModule(moduleName);

        vm.stopPrank();
    }

    function _buildMerkleProof(MerkleProofData[] memory validatorRewards) internal returns (bytes32 root) {
        rewardsMerkleProof = new Merkle();

        rewardsMerkleProofData = new bytes32[](validatorRewards.length);

        for (uint256 i = 0; i < validatorRewards.length; ++i) {
            MerkleProofData memory validatorData = validatorRewards[i];
            rewardsMerkleProofData[i] =
                keccak256(bytes.concat(keccak256(abi.encode(validatorData.node, validatorData.amount))));
        }

        root = rewardsMerkleProof.getRoot(rewardsMerkleProofData);
    }

    function _createRestakingOperator() internal returns (IRestakingOperator) {
        IRestakingOperator operator = pufferModuleManager.createNewRestakingOperator({
            metadataURI: "https://puffer.fi/metadata.json",
            delegationApprover: address(0),
            stakerOptOutWindowBlocks: 0
        });

        IDelegationManager.OperatorDetails memory details =
            operator.EIGEN_DELEGATION_MANAGER().operatorDetails(address(operator));
        assertEq(details.delegationApprover, address(0), "delegation approver");
        assertEq(details.stakerOptOutWindowBlocks, 0, "blocks");
        return operator;
    }

    function getMagicNumber() external pure returns (uint256) {
        return 85858585;
    }
}

struct MerkleProofData {
    address node;
    uint256 amount;
}
