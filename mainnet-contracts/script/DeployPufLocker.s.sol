// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { PufLocker } from "../src/PufLocker.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ROLE_ID_DAO, PUBLIC_ROLE } from "../script/Roles.sol";

/**
 * Check that the simulation
 * add --slow if deploying to a mainnet fork like tenderly (its buggy sometimes)
 *
 *       forge script script/DeployPufLocker.s.sol:DeployPufLocker --rpc-url=$RPC_URL --private-key $PK --vvvv
 *
 *       `forge cache clean`
 *       forge script script/DeployPufLocker.s.sol:DeployPufLocker --rpc-url=$RPC_URL --private-key $PK --broadcast --verify
 */
contract DeployPufLocker is Script {
    AccessManager accessManager;

    PufLocker pufLockerProxy;

    function run() public {
        if (block.chainid == 1) {
            accessManager = AccessManager(0x8c1686069474410E6243425f4a10177a94EBEE11);
        } else if (block.chainid == 17000) {
            // Holesky
            accessManager = AccessManager(0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e);
        } else {
            revert("unsupported chain");
        }

        vm.startBroadcast();

        PufLocker pufLockerImpl = new PufLocker();
        pufLockerProxy = PufLocker(
            address(
                new ERC1967Proxy{ salt: bytes32("PufLocker") }(
                    address(pufLockerImpl), abi.encodeCall(PufLocker.initialize, (address(accessManager)))
                )
            )
        );

        console.log("PufLockerProxy:", address(pufLockerProxy));
        console.log("PufLocker implementation:", address(pufLockerImpl));

        bytes[] memory calldatas = _generateAccessManagerCallData();

        if (block.chainid == 1) {
            bytes memory multicallData = abi.encodeCall(Multicall.multicall, (calldatas));
            console.logBytes(multicallData);
        } else if (block.chainid == 17000) {
            accessManager.multicall(calldatas);
        }
    }

    function _generateAccessManagerCallData() internal view returns (bytes[] memory) {
        bytes[] memory calldatas = new bytes[](2);

        bytes4[] memory publicSelectors = new bytes4[](1);
        publicSelectors[0] = PufLocker.deposit.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(pufLockerProxy), publicSelectors, PUBLIC_ROLE
        );

        bytes4[] memory multisigSelectors = new bytes4[](2);
        multisigSelectors[0] = PufLocker.setIsAllowedToken.selector;
        multisigSelectors[1] = PufLocker.setLockPeriods.selector;

        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(pufLockerProxy), multisigSelectors, ROLE_ID_DAO
        );

        return calldatas;
    }
}
