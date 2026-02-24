// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PermissionedOracle } from "../src/PermissionedOracle.sol";
import { console } from "forge-std/console.sol";

/**
 * @title DeployPermissionedOracle
 * @author Puffer Finance
 * @notice Deploys the PermissionedOracle contract
 * @dev Tracks actual ETH amounts locked by permissioned validators (supports Pectra variable 32-2048 ETH).
 *
 *      forge script script/DeployPermissionedOracle.s.sol:DeployPermissionedOracle \
 *          -vvvv --rpc-url=$RPC_URL --broadcast --verify
 */
contract DeployPermissionedOracle is DeployerHelper {
    function run() public returns (PermissionedOracle) {
        vm.startBroadcast();

        PermissionedOracle oracle = new PermissionedOracle(_getAccessManager());

        vm.label(address(oracle), "PermissionedOracle");
        console.log("Deployed PermissionedOracle at", address(oracle));

        vm.stopBroadcast();

        return oracle;
    }
}
