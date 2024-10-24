// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PufferRevenueDepositor } from "../src/PufferRevenueDepositor.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { GenerateRevenueDepositorCalldata } from "./AccessManagerMigrations/05_GenerateRevenueDepositorCalldata.s.sol";

/**
 * forge script script/DeployRevenueDepositor.s.sol:DeployRevenueDepositor --rpc-url=$RPC_URL --private-key $PK
 */
contract DeployRevenueDepositor is DeployerHelper {
    PufferRevenueDepositor public revenueDepositor;

    bytes public encodedCalldata;

    function run() public {
        GenerateRevenueDepositorCalldata calldataGenerator = new GenerateRevenueDepositorCalldata();

        vm.startBroadcast();

        //@todo Get from RNOs
        address[] memory operatorsAddresses = new address[](7);
        operatorsAddresses[0] = makeAddr("RNO1");
        operatorsAddresses[1] = makeAddr("RNO2");
        operatorsAddresses[2] = makeAddr("RNO3");
        operatorsAddresses[3] = makeAddr("RNO4");
        operatorsAddresses[4] = makeAddr("RNO5");
        operatorsAddresses[5] = makeAddr("RNO6");
        operatorsAddresses[6] = makeAddr("RNO7");

        PufferRevenueDepositor revenueDepositorImpl =
            new PufferRevenueDepositor({ vault: _getPufferVault(), weth: _getWETH(), treasury: _getTreasury() });

        revenueDepositor = PufferRevenueDepositor(
            (
                payable(
                    new ERC1967Proxy{ salt: bytes32("RevenueDepositor") }(
                        address(revenueDepositorImpl),
                        abi.encodeCall(
                            PufferRevenueDepositor.initialize, (address(_getAccessManager()), operatorsAddresses)
                        )
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
