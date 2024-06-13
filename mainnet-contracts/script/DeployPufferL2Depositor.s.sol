// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { PufferL2Depositor } from "../src/PufferL2Depositor.sol";
import { ROLE_ID_DAO, PUBLIC_ROLE } from "../script/Roles.sol";

/**
 * Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/DeployPufferL2Depositor.s.sol:DeployPufferL2Depositor --rpc-url=$RPC_URL --private-key $PK --vvvv
 *
 *       `forge cache clean`
 *       forge script script/DeployPufferL2Depositor.s.sol:DeployPufferL2Depositor --rpc-url=$RPC_URL --private-key $PK --broadcast --verify
 */
contract DeployPufferL2Depositor is Script {
    AccessManager accessManager;

    PufferL2Depositor depositor;
    address weth;

    function run() public {
        if (block.chainid == 1) {
            accessManager = AccessManager(0x8c1686069474410E6243425f4a10177a94EBEE11);
            weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        } else if (block.chainid == 17000) {
            // Holesky
            accessManager = AccessManager(0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e);
            weth = 0x35B1167b4D37931540F4e5189004d1756d1381B0;
        } else {
            revert("unsupported chain");
        }

        vm.startBroadcast();

        depositor = new PufferL2Depositor(address(accessManager), weth);

        bytes[] memory calldatas = new bytes[](2);

        bytes4[] memory publicSelectors = new bytes4[](3);
        publicSelectors[0] = PufferL2Depositor.deposit.selector;
        publicSelectors[1] = PufferL2Depositor.depositETH.selector;
        publicSelectors[2] = PufferL2Depositor.revertIfPaused.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(depositor), publicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory multisigSelectors = new bytes4[](2);
        multisigSelectors[0] = PufferL2Depositor.setMigrator.selector;
        multisigSelectors[1] = PufferL2Depositor.addNewToken.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(depositor), multisigSelectors, ROLE_ID_DAO
        );

        bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));

        console.logBytes(multicallData);
    }
}
