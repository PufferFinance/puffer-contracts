// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

contract AvsRegistryCoordinatorMock {
    event ExpensiveRegister(string socket, address indexed sender, uint256 fee);

    uint256 public constant REGISTRATION_FEE = 0.1 ether;

    function expensiveRegister(string calldata socket) external payable {
        require(msg.value == REGISTRATION_FEE, "Incorrect fee");
        emit ExpensiveRegister(socket, msg.sender, msg.value);
    }
}
