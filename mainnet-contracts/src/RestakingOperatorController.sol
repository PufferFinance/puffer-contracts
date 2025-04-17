// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { IRestakingOperatorController } from "./interface/IRestakingOperatorController.sol";
import { AVSContractsRegistry } from "./AVSContractsRegistry.sol";

/**
 * @title RestakingOperatorController
 * @author Puffer Finance
 * @notice Contract to interact with the RestakingOperators contracts checking if the caller is allowed to call the function
 */
contract RestakingOperatorController is IRestakingOperatorController, AccessManaged {
    mapping(address restakingOperator => address owner) internal _operatorOwners;
    mapping(bytes4 selector => bool isAllowed) internal _allowedSelectors;

    AVSContractsRegistry private immutable _avsContractsRegistry;

    // Selector for the `customCalldataCall` function in the RestakingOperator contract
    bytes4 private constant CUSTOM_CALL_SELECTOR = 0x58fa420c; // bytes4(keccak256("customCalldataCall(address,bytes)(address,bytes,uint256)"))

    constructor(address initialAuthority, address avsContractsRegistry) AccessManaged(initialAuthority) {
        _avsContractsRegistry = AVSContractsRegistry(avsContractsRegistry);
    }

    /**
     * @notice Set the owner of the restaking operator contract
     * @dev Restricted so only the DAO can set the owner
     * @param restakingOperator The address of the restaking operator
     * @param owner The address of the owner
     */
    function setOperatorOwner(address restakingOperator, address owner) external override restricted {
        _operatorOwners[restakingOperator] = owner;
        emit OperatorOwnerUpdated(restakingOperator, owner);
    }

    /**
     * @notice Set the allowed selector for the restaking operator
     * @dev Restricted so only the DAO can set the allowed selector
     * @param selector The selector to set the allowed selector for
     * @param isAllowed The boolean value to set the allowed selector for
     */
    function setAllowedSelector(bytes4 selector, bool isAllowed) external restricted {
        _allowedSelectors[selector] = isAllowed;
        emit SelectorAllowedUpdated(selector, isAllowed);
    }

    /**
     * @notice Custom external call to the restaking operator
     * @dev This function can be called by Operator owners
     * @param restakingOperator The address of the restaking operator
     * @param data The data to call the restaking operator with
     */
    function customExternalCall(address restakingOperator, bytes calldata data) external payable override {
        require(_operatorOwners[restakingOperator] == msg.sender, NotOperatorOwner(restakingOperator, msg.sender));
        bytes4 selector = bytes4(data[:4]);
        require(_allowedSelectors[selector], NotAllowedSelector(selector));
        if (selector == CUSTOM_CALL_SELECTOR) {
            _checkCustomCallData(data);
        }
        (bool success,) = restakingOperator.call{ value: msg.value }(data);
        require(success, CustomCallFailed());
        emit CustomExternalCall(restakingOperator, data, msg.value);
    }

    /**
     * @notice Get the owner of the restaking operator
     * @param restakingOperator The address of the restaking operator
     * @return The address of the owner of the restaking operator
     */
    function getOperatorOwner(address restakingOperator) external view override returns (address) {
        return _operatorOwners[restakingOperator];
    }

    /**
     * @notice Check if the selector is allowed
     * @param selector The selector to check if it is allowed
     * @return The boolean value to check if the selector is allowed
     */
    function isSelectorAllowed(bytes4 selector) external view override returns (bool) {
        return _allowedSelectors[selector];
    }

    /**
     * @notice Check if the custom call is valid
     * @dev Decode calldata sent  to get the avsRegistryCoordinator and the customCalldata
     * @param data The data to check if the custom call is valid
     */
    function _checkCustomCallData(bytes calldata data) private view {
        (address avsRegistryCoordinator, bytes memory customCalldata) = abi.decode(data[4:], (address, bytes));
        require(
            _avsContractsRegistry.isAllowedRegistryCoordinator(avsRegistryCoordinator, customCalldata), Unauthorized()
        );
    }
}
