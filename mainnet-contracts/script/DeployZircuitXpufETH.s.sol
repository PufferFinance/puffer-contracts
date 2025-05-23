// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { Timelock } from "../src/Timelock.sol";
import { BaseScript } from "script/BaseScript.s.sol";

import { ROLE_ID_OPERATIONS_MULTISIG, ROLE_ID_DAO, PUBLIC_ROLE } from "./Roles.sol";

/**
 * // Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/DeployZircuitXpufETH.s.sol:DeployZircuitXpufETH --rpc-url $RPC_URL --account puffer
 *
 *       forge cache clean
 *
 *       forge script script/DeployZircuitXpufETH.s.sol:DeployZircuitXpufETH --rpc-url $RPC_URL --account puffer --broadcast
 */
// api key 654F632647A7D52CBEB3CF4A20CBA5F09B
contract DeployZircuitXpufETH is BaseScript {
    address OPERATIONS_MULTISIG = 0x37bEbCdB82E9428B89eEaB55288da70322079c46;
    address COMMUNITY_MULTISIG = 0x6Ee3C744B9B2dd73f8967E5130dc7599c4fCcF41;
    address PAUSER_MULTISIG = 0x1474F91bEB7B5e7ed9837a9cE1b973d9e7CEFF79;

    address EVERCLEAR_BRIDGE = 0x345a5aDf2fC9fD32aB51d03326EAb2F9b5c5C02D;

    uint256 MINTING_LIMIT = 100 ether;
    uint256 BURNING_LIMIT = 100 ether;

    Timelock timelock;
    AccessManager accessManager;

    xPufETH public xPufETHProxy;

    function run() public broadcast {
        accessManager = new AccessManager(_broadcaster);
        timelock = new Timelock({
            accessManager: address(accessManager),
            communityMultisig: COMMUNITY_MULTISIG,
            operationsMultisig: OPERATIONS_MULTISIG,
            pauser: PAUSER_MULTISIG,
            initialDelay: 7 days
        });

        xPufETH xpufETHImplementation = new xPufETH();

        xPufETHProxy = xPufETH(
            address(
                new ERC1967Proxy{ salt: bytes32("xPufETH") }(
                    address(xpufETHImplementation), abi.encodeCall(xPufETH.initialize, (address(accessManager)))
                )
            )
        );
        console.log("Timelock:", address(timelock));
        console.log("AccessManager:", address(accessManager));
        console.log("xpufETHProxy:", address(xPufETHProxy));
        console.log("xpufETH implementation:", address(xpufETHImplementation));

        // setup the limits for the bridge
        bytes memory setLimitsCalldata =
            abi.encodeWithSelector(xPufETH.setLimits.selector, EVERCLEAR_BRIDGE, MINTING_LIMIT, BURNING_LIMIT);
        accessManager.execute(address(xPufETHProxy), setLimitsCalldata);

        // setup all access manager roles
        bytes[] memory calldatas = _generateAccessManagerCallData();
        accessManager.multicall(calldatas);
    }

    function _generateAccessManagerCallData() internal view returns (bytes[] memory) {
        bytes[] memory calldatas = new bytes[](6);

        calldatas[0] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_DAO, OPERATIONS_MULTISIG, 0);

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.grantRole.selector, ROLE_ID_OPERATIONS_MULTISIG, OPERATIONS_MULTISIG, 0
        );

        bytes4[] memory daoSelectors = new bytes4[](2);
        daoSelectors[0] = xPufETH.setLockbox.selector;
        daoSelectors[1] = xPufETH.setLimits.selector;

        calldatas[2] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(xPufETHProxy), daoSelectors, ROLE_ID_DAO
        );

        bytes4[] memory publicSelectors = new bytes4[](2);
        publicSelectors[0] = xPufETH.mint.selector;
        publicSelectors[1] = xPufETH.burn.selector;

        calldatas[3] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(xPufETHProxy), publicSelectors, PUBLIC_ROLE
        );

        calldatas[4] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, accessManager.ADMIN_ROLE(), address(timelock), 0);

        calldatas[5] =
            abi.encodeWithSelector(AccessManager.revokeRole.selector, accessManager.ADMIN_ROLE(), _broadcaster);

        return calldatas;
    }
}
