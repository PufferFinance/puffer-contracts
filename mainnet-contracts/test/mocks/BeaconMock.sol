// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

contract BeaconMock {
    event StartedStaking();

    error BadValue();

    function deposit(bytes calldata, bytes calldata, bytes calldata, bytes32) external payable {
        if (msg.value != 32 ether) {
            revert BadValue();
        }
        emit StartedStaking();
    }

    function get_deposit_root() external pure returns (bytes32) {
        return bytes32("depositRoot");
    }
}
