// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { PufferL2Depositor } from "../src/PufferL2Depositor.sol";
import { PufLocker } from "../src/PufLocker.sol";
import { ROLE_ID_DAO, PUBLIC_ROLE, ROLE_ID_OPERATIONS_MULTISIG } from "../script/Roles.sol";

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
    PufLocker pufLocker;
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

        address pufLockerImpl = address(new PufLocker());
        pufLocker = PufLocker(
            address(new ERC1967Proxy(pufLockerImpl, abi.encodeCall(PufLocker.initialize, (address(accessManager)))))
        );

        depositor = new PufferL2Depositor(address(accessManager), weth, pufLocker);

        bytes[] memory calldatas = new bytes[](4);

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

        bytes4[] memory lockerPublicSelectors = new bytes4[](1);
        lockerPublicSelectors[0] = PufLocker.deposit.selector;

        calldatas[2] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(pufLocker), lockerPublicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory opsLockerSelectors = new bytes4[](2);
        opsLockerSelectors[0] = PufLocker.setIsAllowedToken.selector;
        opsLockerSelectors[1] = PufLocker.setLockPeriods.selector;

        calldatas[3] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(pufLocker),
            opsLockerSelectors,
            ROLE_ID_OPERATIONS_MULTISIG
        );

        bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));

        console.logBytes(multicallData);
    }
}
