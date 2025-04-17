// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IRestakingOperatorController
 * @author Puffer Finance
 * @notice Interface for the RestakingOperatorController contract
 */
interface IRestakingOperatorController {
    /**
     * @notice Error emitted when a selector is not allowed
     * @param selector The selector that is not allowed
     */
    error NotAllowedSelector(bytes4 selector);

    /**
     * @notice Error emitted when the caller is not the operator owner
     * @param restakingOperator The address of the restaking operator
     * @param caller The address of the caller
     */
    error NotOperatorOwner(address restakingOperator, address caller);

    /**
     * @notice Error emitted when a custom call fails
     */
    error CustomCallFailed();

    /**
     * @notice Error emitted when the caller is not authorized by the AVSContractsRegistry to call the function selector
     */
    error Unauthorized();

    /**
     * @notice Emitted when a custom external call is made
     * @param target The target address of the call
     * @param data The data of the call
     * @param value The value of the call
     */
    event CustomExternalCall(address target, bytes data, uint256 value);

    /**
     * @notice Emitted when the operator owner is updated
     * @param restakingOperator The address of the restaking operator
     * @param newOwner The new owner of the restaking operator
     */
    event OperatorOwnerUpdated(address restakingOperator, address newOwner);

    /**
     * @notice Emitted when a selector is allowed
     * @param selector The selector that is allowed
     * @param isAllowed The boolean value to check if the selector is allowed
     */
    event SelectorAllowedUpdated(bytes4 selector, bool isAllowed);

    /**
     * @notice Set the owner of the restaking operator contract
     * @dev Restricted so only the DAO can set the owner
     * @param restakingOperator The address of the restaking operator
     * @param owner The address of the owner
     */
    function setOperatorOwner(address restakingOperator, address owner) external;

    /**
     * @notice Set the allowed selector for the restaking operator
     * @dev Restricted so only the DAO can set the allowed selector
     * @param selector The selector to set the allowed selector for
     * @param isAllowed The boolean value to set the allowed selector for
     */
    function setAllowedSelector(bytes4 selector, bool isAllowed) external;

    /**
     * @notice Custom external call to the restaking operator
     * @dev Restricted so only the DAO can call the function
     * @param restakingOperator The address of the restaking operator
     * @param data The data to call the restaking operator with
     */
    function customExternalCall(address restakingOperator, bytes calldata data) external payable;

    /**
     * @notice Get the owner of the restaking operator
     * @param restakingOperator The address of the restaking operator
     * @return The address of the owner of the restaking operator
     */
    function getOperatorOwner(address restakingOperator) external view returns (address);

    /**
     * @notice Check if the selector is allowed
     * @param selector The selector to check if it is allowed
     * @return The boolean value to check if the selector is allowed
     */
    function isSelectorAllowed(bytes4 selector) external view returns (bool);
}
