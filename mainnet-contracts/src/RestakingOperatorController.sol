// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import "./interface/IRestakingOperatorController.sol";

/**
 * @title RestakingOperatorController
 * @author Puffer Finance
 * @notice Contract to interact with the RestakingOperators contracts checking if the caller is allowed to call the function
 */
contract RestakingOperatorController is IRestakingOperatorController, AccessManagedUpgradeable {
    // keccak256(abi.encode(uint256(keccak256("RestakingOperatorController.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _RESTAKING_OPERATOR_CONTROLLER_STORAGE =
        0x57d98338337f003a6d3cf061ea46f8870d95148e1bbbcada7b744568bc1fb600;

    /**
     * @custom:storage-location erc7201:RestakingOperator.storage
     * @dev +-----------------------------------------------------------+
     *      |                                                           |
     *      | DO NOT CHANGE, REORDER, REMOVE EXISTING STORAGE VARIABLES |
     *      |                                                           |
     *      +-----------------------------------------------------------+
     */
    struct ControllerStorage {
        mapping(address restakingOperator => address owner) operatorOwners;
        mapping(bytes4 selector => bool isAllowed) allowedSelectors;
    }

    /**
     * @notice Initialize the contract
     * @param initialAuthority The address of the initial authority
     */
    function initialize(address initialAuthority) external initializer {
        __AccessManaged_init(initialAuthority);
    }

    /**
     * @notice Set the owner of the restaking operator contract
     * @dev Restricted so only the DAO can set the owner
     * @param restakingOperator The address of the restaking operator
     * @param owner The address of the owner
     */
    function setOperatorOwner(address restakingOperator, address owner) external override restricted {
        ControllerStorage storage $ = _getControllerStorage();
        $.operatorOwners[restakingOperator] = owner;
        emit OperatorOwnerUpdated(restakingOperator, owner);
    }

    /**
     * @notice Set the allowed selector for the restaking operator
     * @dev Restricted so only the DAO can set the allowed selector
     * @param selector The selector to set the allowed selector for
     * @param isAllowed The boolean value to set the allowed selector for
     */
    function setAllowedSelector(bytes4 selector, bool isAllowed) external restricted {
        ControllerStorage storage $ = _getControllerStorage();
        $.allowedSelectors[selector] = isAllowed;
        emit SelectorAllowedUpdated(selector, isAllowed);
    }

    /**
     * @notice Custom external call to the restaking operator
     * @dev Restricted so only the DAO can call the function
     * @param target The address of the restaking operator
     * @param data The data to call the restaking operator with
     * @param value The value to call the restaking operator with
     */
    function customExternalCall(address target, bytes calldata data, uint256 value) external override {
        ControllerStorage storage $ = _getControllerStorage();
        require($.operatorOwners[msg.sender] == msg.sender, NotOperatorOwner(target, msg.sender));
        bytes4 selector = bytes4(data[:4]);
        require(!$.allowedSelectors[selector], NotAllowedSelector(selector));
        (bool success,) = target.call{ value: value }(data);
        require(success, CustomCallFailed());
        emit CustomExternalCall(target, data, value);
    }

    /**
     * @notice Get the owner of the restaking operator
     * @param restakingOperator The address of the restaking operator
     * @return The address of the owner of the restaking operator
     */
    function getOperatorOwner(address restakingOperator) external view override returns (address) {
        ControllerStorage storage $ = _getControllerStorage();
        return $.operatorOwners[restakingOperator];
    }

    /**
     * @notice Check if the selector is allowed
     * @param selector The selector to check if it is allowed
     * @return The boolean value to check if the selector is allowed
     */
    function isSelectorAllowed(bytes4 selector) external view override returns (bool) {
        ControllerStorage storage $ = _getControllerStorage();
        return $.allowedSelectors[selector];
    }

    /**
     * @notice Get the controller storage
     * @return $ The controller storage
     */
    function _getControllerStorage() internal pure returns (ControllerStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _RESTAKING_OPERATOR_CONTROLLER_STORAGE
        }
    }
}
