pragma solidity ^0.4.24;

contract Proxy {
    function deposit() external returns (uint) {
        uint _amount = IERC20(underlying).balanceOf(msg.sender);
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), _amount);
        return _deposit(_amount, msg.sender);
    }

    function depositWithPermit(address target, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s, address to) external returns (uint) {
        IERC20(underlying).permit(target, address(this), value, deadline, v, r, s);
        uint a;
        IERC20(underlying).safeTransferFrom(target, address(this), value);
        return _deposit(value, to);
    }

    function FAILdepositWithPermit(address target, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s, address to) external returns (uint) {
        IERC20(tokenA).permit(target, address(this), value, deadline, v, r, s);
        uint a;
        IERC20(tokenB).safeTransferFrom(target, address(this), value);
        return _deposit(value, to);
    }

    function FAILdepositWithPermit2(address target, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s, address to) external returns (uint) {
        IERC20(tokenA).permit(target, address(this), value, deadline, v, r, s);
        return _deposit(value, to);
    }
}
