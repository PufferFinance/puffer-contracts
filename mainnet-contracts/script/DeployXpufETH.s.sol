// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { XERC20Lockbox } from "src/XERC20Lockbox.sol";
import {
    ROLE_ID_VT_PRICER,
    ROLE_ID_OPERATIONS_COORDINATOR,
    ROLE_ID_OPERATIONS_MULTISIG,
    ROLE_ID_DAO,
    PUBLIC_ROLE
} from "./Roles.sol";

/**
 * // Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/DeployXpufETH.s.sol:DeployXpufETH --rpc-url $RPC_URL --account puffer
 *
 *       forge cache clean
 *
 *       forge script script/DeployXpufETH.s.sol:DeployXpufETH --rpc-url $RPC_URL --account puffer --broadcast
 */
contract DeployXpufETH is Script {
    address ACCCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;
    address PUFFER_VAULT = 0xD9A442856C234a39a81a089C06451EBAa4306a72;

    xPufETH public xPufETHProxy;
    XERC20Lockbox public xERC20Lockbox;

    function run() public {
        vm.startBroadcast();

        xPufETH xpufETHImplementation = new xPufETH();

        xPufETHProxy = xPufETH(
            address(
                new ERC1967Proxy{ salt: bytes32("xPufETH") }(
                    address(xpufETHImplementation), abi.encodeCall(xPufETH.initialize, (ACCCESS_MANAGER))
                )
            )
        );

        // Deploy the lockbox
        xERC20Lockbox = new XERC20Lockbox({ xerc20: address(xPufETHProxy), erc20: address(PUFFER_VAULT) });

        console.log("xpufETHProxy:", address(xPufETHProxy));
        console.log("xpufETH implementation:", address(xpufETHImplementation));
        console.log("xERC20Lockbox:", address(xERC20Lockbox));

        _generateAccessManagerCallData();
    }

    function _generateAccessManagerCallData() internal view {
        bytes[] memory calldatas = new bytes[](2);

        bytes4[] memory daoSelectors = new bytes4[](2);
        daoSelectors[0] = xPufETH.setLockbox.selector;
        daoSelectors[1] = xPufETH.setLimits.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(xPufETHProxy), daoSelectors, ROLE_ID_DAO
        );

        bytes4[] memory publicSelectors = new bytes4[](2);
        publicSelectors[0] = xPufETH.mint.selector;
        publicSelectors[1] = xPufETH.burn.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(xPufETHProxy), publicSelectors, PUBLIC_ROLE
        );

        bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));
        bytes memory setLockboxCalldata = abi.encodeCall(xPufETH.setLockbox, address(xERC20Lockbox));

        // Ops multisig needs to queue access manager calldata
        console.log("AccessManagerCalldata: ");
        console.logBytes(multicallData);

        // Ops multisig can directly call this
        console.log("xPufETHProxy calldata: ");
        console.logBytes(setLockboxCalldata);
    }
}
