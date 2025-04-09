// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IDelegationManager } from "../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IAllocationManager } from "../src/interface/Eigenlayer-Slashing/IAllocationManager.sol";
import { IRewardsCoordinator } from "../src/interface/Eigenlayer-Slashing/IRewardsCoordinator.sol";
import { Unauthorized, InvalidAddress } from "./Errors.sol";
import { IPufferModuleManager } from "./interface/IPufferModuleManager.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title RestakingOperator
 * @author Puffer Finance
 * @notice PufferModule
 * @custom:security-contact security@puffer.fi
 */
contract RestakingOperator is IERC1271, Initializable, AccessManagedUpgradeable {
    using Address for address;

    // keccak256(abi.encode(uint256(keccak256("RestakingOperator.storage")) - 1)) & ~bytes32(uint256(0xff))
    // slither-disable-next-line unused-state

    address private immutable RESTAKING_OPERATOR_CONTROLLER;

    bytes32 private constant _RESTAKING_OPERATOR_STORAGE =
        0x2182a68f8e463a6b4c76f5de5bb25b7b51ccc88cb3b9ba6c251c356b50555100;

    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 internal constant _EIP1271_MAGIC_VALUE = 0x1626ba7e;
    // Invalid signature value (EIP-1271)
    bytes4 internal constant _EIP1271_INVALID_VALUE = 0xffffffff;

    /**
     * @custom:storage-location erc7201:RestakingOperator.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct RestakingOperatorStorage {
        mapping(bytes32 digestHash => address signer) hashSigners;
    }

    /**
     * @dev Upgradeable contract from EigenLayer
     */
    IRewardsCoordinator public immutable EIGEN_REWARDS_COORDINATOR;

    /**
     * @dev Upgradeable contract from EigenLayer
     */
    IDelegationManager public immutable EIGEN_DELEGATION_MANAGER;

    /**
     * @dev Upgradeable contract from EigenLayer
     */
    IAllocationManager public immutable EIGEN_ALLOCATION_MANAGER;

    /**
     * @dev Upgradeable Puffer Module Manager
     */
    IPufferModuleManager public immutable PUFFER_MODULE_MANAGER;

    modifier onlyAuthorized() {
        require(
            msg.sender == RESTAKING_OPERATOR_CONTROLLER || msg.sender == address(PUFFER_MODULE_MANAGER), Unauthorized()
        );
        _;
    }

    // We use constructor to set the immutable variables
    constructor(
        IDelegationManager delegationManager,
        IAllocationManager allocationManager,
        IPufferModuleManager moduleManager,
        IRewardsCoordinator rewardsCoordinator,
        address restakingOperatorController
    ) {
        if (address(delegationManager) == address(0)) {
            revert InvalidAddress();
        }
        if (address(allocationManager) == address(0)) {
            revert InvalidAddress();
        }
        if (address(moduleManager) == address(0)) {
            revert InvalidAddress();
        }
        if (address(rewardsCoordinator) == address(0)) {
            revert InvalidAddress();
        }
        if (address(restakingOperatorController) == address(0)) {
            revert InvalidAddress();
        }
        EIGEN_DELEGATION_MANAGER = delegationManager;
        EIGEN_ALLOCATION_MANAGER = allocationManager;
        PUFFER_MODULE_MANAGER = moduleManager;
        EIGEN_REWARDS_COORDINATOR = rewardsCoordinator;
        RESTAKING_OPERATOR_CONTROLLER = restakingOperatorController;
        _disableInitializers();
    }

    function initialize(address initialAuthority, string calldata metadataURI, uint32 allocationDelay)
        external
        initializer
    {
        __AccessManaged_init(initialAuthority);
        // Delegation approve is address(0) because we want everybody to be able to delegate to us
        EIGEN_DELEGATION_MANAGER.registerAsOperator(address(0), allocationDelay, metadataURI);
    }

    /**
     * @notice Updates a signature proof by setting the signer address of the message hash
     * @param digestHash is message hash
     * @param signer is the signer address
     * @dev Restricted to the PufferModuleManager or the RestakingOperatorController
     */
    function updateSignatureProof(bytes32 digestHash, address signer) external virtual onlyAuthorized {
        RestakingOperatorStorage storage $ = _getRestakingOperatorStorage();

        $.hashSigners[digestHash] = signer;
    }

    /**
     * @notice Registers msg.sender as an operator
     * @param registrationParams is the struct with new operator details
     * @dev Restricted to the PufferModuleManager or the RestakingOperatorController
     */
    function registerOperatorToAVS(IAllocationManager.RegisterParams calldata registrationParams)
        external
        virtual
        onlyAuthorized
    {
        EIGEN_ALLOCATION_MANAGER.registerForOperatorSets(address(this), registrationParams);
    }

    /**
     * @notice Deregisters msg.sender as an operator
     * @param deregistrationParams is the struct with new operator details
     * @dev Restricted to the PufferModuleManager or the RestakingOperatorController
     */
    function deregisterOperatorFromAVS(IAllocationManager.DeregisterParams calldata deregistrationParams)
        external
        virtual
        onlyAuthorized
    {
        EIGEN_ALLOCATION_MANAGER.deregisterFromOperatorSets(deregistrationParams);
    }

    /**
     * @notice Does a custom call to `target` with `customCalldata`
     * @param target is the address of the contract to call
     * @param customCalldata is the calldata to send to the target contract
     * @dev Restricted to the PufferModuleManager or the RestakingOperatorController
     */
    function customCalldataCall(address target, bytes calldata customCalldata)
        external
        payable
        virtual
        onlyAuthorized
        returns (bytes memory response)
    {
        return target.functionCallWithValue(customCalldata, msg.value);
    }

    /**
     * @notice Sets the rewards claimer to `claimer` for the RestakingOperator
     * @param claimer is the address of the claimer
     * @dev Restricted to PufferModuleManager or the RestakingOperatorController
     */
    function callSetClaimerFor(address claimer) external virtual onlyAuthorized {
        EIGEN_REWARDS_COORDINATOR.setClaimerFor(claimer);
    }

    /**
     * @notice Verifies that the signer is the owner of the signing contract.
     */
    function isValidSignature(bytes32 digestHash, bytes calldata signature) external view override returns (bytes4) {
        RestakingOperatorStorage storage $ = _getRestakingOperatorStorage();

        address signer = $.hashSigners[digestHash];

        // Validate signatures
        if (signer != address(0) && ECDSA.recover(digestHash, signature) == signer) {
            return _EIP1271_MAGIC_VALUE;
        } else {
            return _EIP1271_INVALID_VALUE;
        }
    }

    function _getRestakingOperatorStorage() internal pure returns (RestakingOperatorStorage storage $) {
        // solhint-disable-next-line
        assembly {
            $.slot := _RESTAKING_OPERATOR_STORAGE
        }
    }
}
