// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_L1_REWARD_MANAGER } from "../../script/Roles.sol";

import { BridgeMock } from "l2-contracts/test/mocks/BridgeMock.sol";

/**
 * @title GenerateAccessManagerCalldata1
 * @author Puffer Finance
 * @notice Generates the AccessManager call data to setup the public access
 * The returned calldata is queued and executed by the Operations Multisig
 * 1. timelock.queueTransaction(address(accessManager), encodedMulticall, 1)
 * 2. ... 7 days later ...
 * 3. timelock.executeTransaction(address(accessManager), encodedMulticall, 1)
 */
contract GenerateBridgeMockCalldata is Script {
    function generateBridgeMockCalldata(address bridge, address l1Bridge, address l2bridge)
        public
        pure
        returns (bytes memory encodedMulticall)
    {
        bytes[] memory calldatas = new bytes[](3);

        bytes4[] memory rewardManagerSelectors = new bytes4[](1);
        rewardManagerSelectors[0] = BridgeMock.xcall.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, bridge, rewardManagerSelectors, ROLE_ID_L1_REWARD_MANAGER
        );

        // For simplicity, grant the same role to both reward managers
        calldatas[1] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_L1_REWARD_MANAGER, l1Bridge, 0);
        calldatas[2] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_L1_REWARD_MANAGER, l2bridge, 0);

        return abi.encodeCall(Multicall.multicall, (calldatas));
    }
}
