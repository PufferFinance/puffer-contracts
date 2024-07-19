
// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BaseScript } from "./BaseScript.s.sol";
import { ROLE_ID_OPERATIONS_MULTISIG, PUBLIC_ROLE } from "../script/Roles.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { Timelock } from "../src/Timelock.sol";
import {L2RewardManager} from "../src/l2-contracts/L2RewardManager.sol";
/**
 * @title DeployL2RewardManager
 * @author Puffer Finance
 * @notice Deploys L2RewardManager
 * @dev
 *
 *
 *         NOTE:
 *
 *         If you ran the deployment script, but did not `--broadcast` the transaction, it will still update your local chainId-deployment.json file.
 *         Other scripts will fail because addresses will be updated in deployments file, but the deployment never happened.
 *
 *         BaseScript.sol holds the private key logic, if you don't have `PK` ENV variable, it will use the default one PK from `makeAddr("pufferDeployer")`
 *
 *         PK=${deployer_pk} forge script script/DeployL2RewardManager.s.sol:DeployL2RewardManager -vvvv --rpc-url=... --broadcast
 */
contract DeployL2RewardManager is BaseScript {

    address _CONNEXT = 0x8247ed6d0a344eeae4edBC7e44572F1B70ECA82A; //@todo change for mainnet

    function run() public broadcast {
        AccessManager accessManager = new AccessManager(_broadcaster);

        console.log("AccessManager", address(accessManager));

        L2RewardManager newImplementation = new L2RewardManager(address(_CONNEXT));
        console.log("L2RewardManager Implementation", address(newImplementation));

        ERC1967Proxy proxy = new ERC1967Proxy(address(newImplementation), abi.encodeCall(L2RewardManager.initialize, (address(accessManager))));
        console.log("L2RewardManager Proxy", address(proxy));

        bytes4[] memory bridgeContractSelector = new bytes4[](1);
        bridgeContractSelector[0] = L2RewardManager.xReceive.selector;

        // TODO - create new role for bridge contract
        bytes memory cd = abi.encodeWithSelector(AccessManager.setTargetFunctionRole.selector, address(proxy), bridgeContractSelector, PUBLIC_ROLE);

        console.logBytes(cd);
        accessManager.execute(address(accessManager), cd);

        accessManager.grantRole(PUBLIC_ROLE, _CONNEXT, 0);
    }
}