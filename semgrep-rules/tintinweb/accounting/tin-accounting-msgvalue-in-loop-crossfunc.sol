pragma solidity ^0.8.0;

struct Order { 
    address to;
    uint amount;
}

contract MsgLoop {
    address owner;

    function batchFillOrder(Order[] calldata orders) external payable {
        for (uint256 i = 0; i < orders.length; i++) {
            fillOrder(orders[i]);
        }
    }

    function fillOrder(Order calldata order) public payable {
        // do something
        require(msg.value >= order.amount, "invalid amount");
        (bool success, ) = payable(order.to).call{value: order.amount}("");
        if (!success) {
            revert();
        }
        // do something
    }
}
