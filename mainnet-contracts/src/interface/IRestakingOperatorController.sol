// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

interface IRestakingOperatorController {
    error NotAllowedSelector(bytes4 selector);
    error NotOperatorOwner(address restakingOperator, address caller);
    error CustomCallFailed();

    event CustomExternalCall(address target, bytes data, uint256 value);
    event OperatorOwnerUpdated(address restakingOperator, address newOwner);
    event SelectorAllowedUpdated(bytes4 selector, bool isAllowed);

    function customExternalCall(address target, bytes calldata data, uint256 value) external;
    function setOperatorOwner(address restakingOperator, address owner) external;
    function setAllowedSelector(bytes4 selector, bool isAllowed) external;
    function getOperatorOwner(address restakingOperator) external view returns (address);
    function isSelectorAllowed(bytes4 selector) external view returns (bool);
}
