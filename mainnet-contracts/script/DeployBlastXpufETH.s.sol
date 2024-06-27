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
import { NoImplementation } from "../src/NoImplementation.sol";

import { ROLE_ID_OPERATIONS_MULTISIG, ROLE_ID_DAO, PUBLIC_ROLE } from "./Roles.sol";

/**
 * // Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/DeployBlastXpufETH.s.sol:DeployBlastXpufETH --rpc-url https://base.gateway.tenderly.co/INYQEXOxL7vvF3irQ1qmd --account puffer
 *
 *       forge cache clean
 *
 *       forge script script/DeployBlastXpufETH.s.sol:DeployBlastXpufETH --rpc-url $RPC_URL --account puffer --broadcast
 */
contract DeployBlastXpufETH is BaseScript {
    address OPERATIONS_MULTISIG = 0x17A65Ee2E009710bd0357B8138aC2C8A061A163d;
    address COMMUNITY_MULTISIG = 0xB9E953bF40420b3F13F740bCC751ebf274a30068;
    address PAUSER_MULTISIG = 0x1Da90bf2B36897cAD6E75321501EA068Cd645D07;

    // https://blastscan.io/address/0x4200000000000000000000000000000000000010
    address BLAST_BRIDGE = 0x4200000000000000000000000000000000000010; // todo confirm with Blast team

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

        address noImpl = address(new NoImplementation());
        xPufETHProxy = xPufETH(address(new ERC1967Proxy{ salt: bytes32("xPufETH") }(address(noImpl), "")));
        xPufETH xpufETHImplementation = new xPufETH(address(xPufETHProxy), BLAST_BRIDGE);
        // Initialize Vault
        NoImplementation(payable(address(xPufETHProxy))).upgradeToAndCall(
            address(xpufETHImplementation), abi.encodeCall(xPufETH.initialize, (address(accessManager)))
        );

        console.log("Timelock:", address(timelock));
        console.log("AccessManager:", address(accessManager));
        console.log("xpufETHProxy:", address(xPufETHProxy));
        console.log("xpufETH implementation:", address(xpufETHImplementation));

        // setup the limits for the bridge
        bytes memory setLimitsCalldata =
            abi.encodeWithSelector(xPufETH.setLimits.selector, BLAST_BRIDGE, MINTING_LIMIT, BURNING_LIMIT);
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
