// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "./ISignatureUtils.sol";
import "./IPauserRegistry.sol";
import "./IStrategy.sol";

interface IAVSDirectoryErrors {
    /// Operator Status
    /// @dev Thrown when an operator does not exist in the DelegationManager
    error OperatorNotRegisteredToEigenLayer();
    /// @dev Thrown when an operator is already registered to an AVS.
    error OperatorNotRegisteredToAVS();
    /// @dev Thrown when `operator` is already registered to the AVS.
    error OperatorAlreadyRegisteredToAVS();
    /// @dev Thrown when attempting to spend a spent eip-712 salt.
    error SaltSpent();
}

interface IAVSDirectoryTypes {
    /// @notice Enum representing the registration status of an operator with an AVS.
    /// @notice Only used by legacy M2 AVSs that have not integrated with operatorSets.
    enum OperatorAVSRegistrationStatus {
        UNREGISTERED, // Operator not registered to AVS
        REGISTERED // Operator registered to AVS
    }

    /**
     * @notice Struct representing the registration status of an operator with an operator set.
     * Keeps track of last deregistered timestamp for slashability concerns.
     * @param registered whether the operator is registered with the operator set
     * @param lastDeregisteredTimestamp the timestamp at which the operator was last deregistered
     */
    struct OperatorSetRegistrationStatus {
        bool registered;
        uint32 lastDeregisteredTimestamp;
    }
}

interface IAVSDirectoryEvents is IAVSDirectoryTypes {
    /**
     *  @notice Emitted when an operator's registration status with an AVS id updated
     *  @notice Only used by legacy M2 AVSs that have not integrated with operatorSets.
     */
    event OperatorAVSRegistrationStatusUpdated(
        address indexed operator, address indexed avs, OperatorAVSRegistrationStatus status
    );

    /// @notice Emitted when an AVS updates their metadata URI (Uniform Resource Identifier).
    /// @dev The URI is never stored; it is simply emitted through an event for off-chain indexing.
    event AVSMetadataURIUpdated(address indexed avs, string metadataURI);

    /// @notice Emitted when an AVS migrates to using operator sets.
    event AVSMigratedToOperatorSets(address indexed avs);

    /// @notice Emitted when an operator is migrated from M2 registration to operator sets.
    event OperatorMigratedToOperatorSets(address indexed operator, address indexed avs, uint32[] operatorSetIds);
}
