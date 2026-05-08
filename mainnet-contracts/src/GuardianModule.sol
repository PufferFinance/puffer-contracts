// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { IGuardianModule, GuardianSessionProof } from "./interface/IGuardianModule.sol";
import { Unauthorized, InvalidAddress } from "./Errors.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { LibGuardianMessages } from "./LibGuardianMessages.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StoppedValidatorInfo } from "./struct/StoppedValidatorInfo.sol";
import {
    ISessionRegistry,
    PublicIdentity,
    CVMSession
} from "@automata-network/automata-tee-workload-measurement/interfaces/registries/ISessionRegistry.sol";
import { LibKey } from "@automata-network/automata-tee-workload-measurement/lib/LibKey.sol";
import { ALGO_ID_ES256K } from "@automata-network/automata-tee-workload-measurement/types/Constants.sol";

/**
 * @title Guardian module
 * @author Puffer Finance
 * @dev This contract is responsible for storing enclave keys and validation of guardian's EOA/Enclave signatures
 * @custom:security-contact security@puffer.fi
 */
contract GuardianModule is AccessManaged, IGuardianModule {
    using ECDSA for bytes32;
    using Address for address;
    using Address for address payable;
    using MessageHashUtils for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Uncompressed ECDSA keys are 65 bytes long
     */
    uint256 internal constant _ECDSA_KEY_LENGTH = 65;

    /**
     * @dev Ejection threshold balance. If the balance of the Validator falls below this value, the Guardian will eject the Validator
     */
    uint256 internal constant _EJECTION_THRESHOLD_BALANCE = 31.75 ether;

    /**
     * @notice Freshness number of blocks
     */
    uint256 public immutable FRESHNESS_BLOCKS;

    /**
     * @notice Session Registry smart contract
     */
    ISessionRegistry public immutable SESSION_REGISTRY;

    /**
     * @dev Guardians set
     */
    EnumerableSet.AddressSet private _guardians;

    /**
     * @dev Threshold for the guardians. If the number of signatures/proofs is below this threshold, the action will not be authorized
     */
    uint256 internal _threshold;

    /**
     * @dev This variable is for the Guardian's to coordinate on when to eject Puffer validators
     */
    uint256 internal _ejectionThreshold;

    /**
     * @dev Enclave data
     * The guardian doesn't know the Secret Key of an enclave wallet
     */
    struct GuardianData {
        bytes enclavePubKey;
        address enclaveAddress;
    }

    /**
     * @dev Mapping of a Guardian's EOA to enclave data
     */
    mapping(address guardian => GuardianData data) internal _guardianEnclaves;

    /**
     * @dev Mapping of allowed workload IDs (can be added/removed)
     */
    mapping(bytes32 workloadId => bool allowed) internal _allowedWorkloads;

    constructor(
        ISessionRegistry sessionRegistry,
        address[] memory guardians,
        uint256 threshold,
        address pufferAuthority,
        uint256 freshnessBlocks
    ) payable AccessManaged(pufferAuthority) {
        if (address(sessionRegistry) == address(0)) {
            revert InvalidAddress();
        }
        if (address(pufferAuthority) == address(0)) {
            revert InvalidAddress();
        }
        SESSION_REGISTRY = sessionRegistry;
        for (uint256 i = 0; i < guardians.length; ++i) {
            _addGuardian(guardians[i]);
        }
        _setEjectionThreshold(_EJECTION_THRESHOLD_BALANCE);
        _setThreshold(threshold);

        FRESHNESS_BLOCKS = freshnessBlocks;
    }

    receive() external payable { }

    /*
     * @notice Splits the funds among the guardians
     * @dev This function is called to distribute the balance of the contract equally among the guardians
     *      It calculates the amount per guardian and transfers it to each guardian's address
     *      No need for reentrancy checks because guardians are expected to be EOA's accounts
     */
    function splitGuardianFunds() public {
        uint256 numGuardians = _guardians.length();

        uint256 amountPerGuardian = address(this).balance / numGuardians;

        for (uint256 i = 0; i < numGuardians; ++i) {
            // slither-disable-start reentrancy-unlimited-gas
            // slither-disable-next-line calls-loop
            payable(_guardians.at(i)).sendValue(amountPerGuardian);
            // slither-disable-end reentrancy-unlimited-gas
        }
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function validateSkipProvisioning(bytes32 moduleName, uint256 skippedIndex, bytes[] calldata eoaSignatures)
        external
        view
    {
        bytes32 signedMessageHash = LibGuardianMessages._getSkipProvisioningMessage(moduleName, skippedIndex);

        // Check the signatures
        bool validSignatures =
            validateGuardiansEOASignatures({ eoaSignatures: eoaSignatures, signedMessageHash: signedMessageHash });

        if (!validSignatures) {
            revert Unauthorized();
        }
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function validateProvisionNode(
        uint256 pufferModuleIndex,
        bytes calldata pubKey,
        bytes calldata signature,
        bytes calldata withdrawalCredentials,
        bytes32 depositDataRoot,
        bytes[] calldata enclaveSignatures
    ) external view {
        // Recreate the message hash
        bytes32 signedMessageHash = LibGuardianMessages._getBeaconDepositMessageToBeSigned({
            pufferModuleIndex: pufferModuleIndex,
            pubKey: pubKey,
            signature: signature,
            withdrawalCredentials: withdrawalCredentials,
            depositDataRoot: depositDataRoot
        });

        // Check the signatures
        bool validSignatures = validateGuardiansEnclaveSignatures({
            enclaveSignatures: enclaveSignatures,
            signedMessageHash: signedMessageHash
        });

        if (!validSignatures) {
            revert Unauthorized();
        }
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function validateBatchWithdrawals(StoppedValidatorInfo[] calldata validatorInfos, bytes[] calldata eoaSignatures)
        external
        view
    {
        bytes32 signedMessageHash = LibGuardianMessages._getHandleBatchWithdrawalMessage(validatorInfos);

        // Check the signatures
        bool validSignatures =
            validateGuardiansEOASignatures({ eoaSignatures: eoaSignatures, signedMessageHash: signedMessageHash });

        if (!validSignatures) {
            revert Unauthorized();
        }
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function validateTotalNumberOfValidators(
        uint256 newNumberOfValidators,
        uint256 epochNumber,
        bytes[] calldata eoaSignatures
    ) external view {
        // Recreate the message hash
        bytes32 signedMessageHash =
            LibGuardianMessages._getSetNumberOfValidatorsMessage(newNumberOfValidators, epochNumber);

        // Check the signatures
        bool validSignatures =
            validateGuardiansEOASignatures({ eoaSignatures: eoaSignatures, signedMessageHash: signedMessageHash });

        if (!validSignatures) {
            revert Unauthorized();
        }
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function validateGuardiansEOASignatures(bytes[] calldata eoaSignatures, bytes32 signedMessageHash)
        public
        view
        returns (bool)
    {
        return _validateSignatures(_guardians.values(), eoaSignatures, signedMessageHash);
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function validateGuardiansEnclaveSignatures(bytes[] calldata enclaveSignatures, bytes32 signedMessageHash)
        public
        view
        returns (bool)
    {
        return _validateSignatures(getGuardiansEnclaveAddresses(), enclaveSignatures, signedMessageHash);
    }

    /**
     * @inheritdoc IGuardianModule
     * @dev Restricted to the DAO
     */
    function setEjectionThreshold(uint256 newThreshold) external restricted {
        _setEjectionThreshold(newThreshold);
    }

    /**
     * @inheritdoc IGuardianModule
     * @dev Restricted to the DAO
     */
    function setAllowedWorkload(bytes32 workloadId, bool allowed) external restricted {
        require(workloadId != bytes32(0), WorkloadNotAllowed());
        _allowedWorkloads[workloadId] = allowed;
        emit WorkloadAllowanceChanged(workloadId, allowed);
    }

    /**
     * @inheritdoc IGuardianModule
     * @dev Restricted to the DAO
     */
    function addGuardian(address newGuardian) external restricted {
        splitGuardianFunds();
        _addGuardian(newGuardian);
    }

    /**
     * @inheritdoc IGuardianModule
     * @dev Restricted to the DAO
     */
    function removeGuardian(address guardian) external restricted {
        splitGuardianFunds();

        bool success = _guardians.remove(guardian);
        if (success) {
            emit GuardianRemoved(guardian);
        }

        if (_guardians.length() < _threshold) {
            revert InvalidThreshold(_threshold);
        }
    }

    /**
     * @inheritdoc IGuardianModule
     * @dev Restricted to the DAO
     */
    function setThreshold(uint256 newThreshold) external restricted {
        _setThreshold(newThreshold);
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function getThreshold() external view returns (uint256) {
        return _threshold;
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function getGuardians() external view returns (address[] memory) {
        return _guardians.values();
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function rotateGuardianKey(uint256 blockNumber, bytes calldata pubKey, GuardianSessionProof calldata proof)
        external
    {
        // The ownerKey is provided by the operator during TEE workload deployment (via atakit deploy --owner-private-key).
        // The CVM agent binds the ownerKey to the session, so a valid session signature attests that the message originated from the operator.
        require(proof.ownerKey.typeId == ALGO_ID_ES256K, InvalidECDSAPubKey());
        require(proof.ownerKey.key.length == _ECDSA_KEY_LENGTH, InvalidECDSAPubKey());

        address guardian = address(uint160(uint256(keccak256(proof.ownerKey.key[1:]))));

        if (!_guardians.contains(guardian)) {
            revert Unauthorized();
        }

        if (pubKey.length != _ECDSA_KEY_LENGTH) {
            revert InvalidECDSAPubKey();
        }

        if ((block.number - blockNumber) > FRESHNESS_BLOCKS) {
            revert StaleEvidence();
        }

        // Since rotateGuardianKey is called infrequently, blockNumber-based freshness is used for replay protection instead of a nonce.
        bytes32 signedMessageHash =
            keccak256(abi.encode("ROTATE_GUARDIAN_KEY", address(this), block.chainid, blockNumber, pubKey));
        bool isValid = SESSION_REGISTRY.verifySessionSignature(
            proof.sessionId, proof.sessionKey, signedMessageHash, proof.signature
        );
        if (!isValid) {
            revert InvalidSignature();
        }

        bytes32 ownerFingerprint = SESSION_REGISTRY.getSessionOwner(proof.sessionId);
        require(ownerFingerprint == LibKey.computeKeyFingerprint(proof.ownerKey), InvalidECDSAPubKey());

        CVMSession memory session = SESSION_REGISTRY.getSession(proof.sessionId);
        require(_allowedWorkloads[session.workloadId], WorkloadNotAllowed());

        // pubKey[1:] means we need to strip the first byte '0x' if we want to get the correct address
        address computedAddress = address(uint160(uint256(keccak256(pubKey[1:]))));

        _guardianEnclaves[guardian].enclaveAddress = computedAddress;
        _guardianEnclaves[guardian].enclavePubKey = pubKey;

        emit RotatedGuardianKey(guardian, computedAddress, pubKey);
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function getEjectionThreshold() external view returns (uint256) {
        return _ejectionThreshold;
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function getGuardiansEnclaveAddress(address guardian) external view returns (address) {
        return _guardianEnclaves[guardian].enclaveAddress;
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function getGuardiansEnclaveAddresses() public view returns (address[] memory) {
        uint256 guardiansLength = _guardians.length();
        address[] memory enclaveAddresses = new address[](guardiansLength);

        for (uint256 i; i < guardiansLength; ++i) {
            // If the guardian doesn't have an enclave address, we use `0xdead` address
            // The reason for this is that we use .tryRecover in signature verification, and a valid signature can be crafted to recover to address(0)
            address enclaveAddress = _guardianEnclaves[_guardians.at(i)].enclaveAddress == address(0)
                ? address(0x000000000000000000000000000000000000dEaD)
                : _guardianEnclaves[_guardians.at(i)].enclaveAddress;
            enclaveAddresses[i] = enclaveAddress;
        }

        return enclaveAddresses;
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function getGuardiansEnclavePubkeys() external view returns (bytes[] memory) {
        uint256 guardiansLength = _guardians.length();
        bytes[] memory enclavePubkeys = new bytes[](guardiansLength);

        for (uint256 i; i < guardiansLength; ++i) {
            enclavePubkeys[i] = _guardianEnclaves[_guardians.at(i)].enclavePubKey;
        }

        return enclavePubkeys;
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function isGuardian(address account) external view returns (bool) {
        return _guardians.contains(account);
    }

    /**
     * @inheritdoc IGuardianModule
     */
    function isWorkloadAllowed(bytes32 workloadId) external view returns (bool) {
        return _allowedWorkloads[workloadId];
    }

    function _addGuardian(address newGuardian) internal {
        if (newGuardian == address(0)) {
            revert InvalidAddress();
        }
        bool success = _guardians.add(newGuardian);
        if (!success) {
            revert InvalidAddress();
        }

        emit GuardianAdded(newGuardian);
    }

    function _setThreshold(uint256 newThreshold) internal {
        if (newThreshold > _guardians.length()) {
            revert InvalidThreshold(newThreshold);
        }
        if (newThreshold == 0) {
            revert InvalidThreshold(newThreshold);
        }
        emit ThresholdChanged(_threshold, newThreshold);
        _threshold = newThreshold;
    }

    function _setEjectionThreshold(uint256 newThreshold) internal {
        if (newThreshold >= 32 ether) {
            revert InvalidThreshold(newThreshold);
        }

        emit EjectionThresholdChanged(_ejectionThreshold, newThreshold);
        _ejectionThreshold = newThreshold;
    }

    /**
     * @dev Validates the signatures of the provided signers
     * @param signers The array of signers
     * @param signatures The array of signatures
     * @param signedMessageHash The hash of the signed message
     * @return A boolean indicating whether the signatures are valid
     */
    function _validateSignatures(address[] memory signers, bytes[] calldata signatures, bytes32 signedMessageHash)
        internal
        view
        returns (bool)
    {
        uint256 validSignatures;

        // We only count signature as valid if it's from the correct signer
        for (uint256 i; i < signers.length; ++i) {
            (address currentSigner, ECDSA.RecoverError recoverError,) =
                ECDSA.tryRecover(signedMessageHash, signatures[i]);
            if (recoverError == ECDSA.RecoverError.NoError) {
                if (currentSigner == signers[i]) {
                    ++validSignatures;
                }
            }
        }

        return validSignatures < _threshold ? false : true;
    }
}
