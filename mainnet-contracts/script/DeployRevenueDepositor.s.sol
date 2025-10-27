// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PufferRevenueDepositor } from "../src/PufferRevenueDepositor.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { GenerateRevenueDepositorCalldata } from "./AccessManagerMigrations/06_GenerateRevenueDepositorCalldata.s.sol";

/**
 * forge script script/DeployRevenueDepositor.s.sol:DeployRevenueDepositor --rpc-url=$RPC_URL --private-key $PK
 */
contract DeployRevenueDepositor is DeployerHelper {
    PufferRevenueDepositor public revenueDepositor;

    bytes public encodedCalldata;

    function run() public {
        GenerateRevenueDepositorCalldata calldataGenerator = new GenerateRevenueDepositorCalldata();

        vm.startBroadcast();

        PufferRevenueDepositor revenueDepositorImpl =
            new PufferRevenueDepositor({ vault: _getPufferVault(), weth: _getWETH(), aeraVault: _getAeraVault() });

        revenueDepositor = PufferRevenueDepositor(
            (
                payable(
                    new ERC1967Proxy{ salt: bytes32("RevenueDepositor") }(
                        address(revenueDepositorImpl),
                        abi.encodeCall(PufferRevenueDepositor.initialize, (address(_getAccessManager())))
                    )
                )
            )
        );

        vm.label(address(revenueDepositor), "PufferRevenueDepositorProxy");
        vm.label(address(revenueDepositorImpl), "PufferRevenueDepositorImplementation");

        encodedCalldata = calldataGenerator.run({
            revenueDepositorProxy: address(revenueDepositor),
            operationsMultisig: _getOPSMultisig()
        });

        console.log("Queue from Timelock -> AccessManager", _getAccessManager());
        console.logBytes(encodedCalldata);

        if (block.chainid == holesky) {
            (bool success,) = address(_getAccessManager()).call(encodedCalldata);
            require(success, "AccessManager.call failed");
        }

        vm.stopBroadcast();
    }
}
