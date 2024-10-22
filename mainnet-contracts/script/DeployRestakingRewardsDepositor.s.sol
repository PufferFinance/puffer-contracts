// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PufferRestakingRewardsDepositor } from "../src/PufferRestakingRewardsDepositor.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { GenerateRestakingRewardsDepositorCalldata } from
    "./AccessManagerMigrations/05_GenerateRestakingRewardsDepositorCalldata.s.sol";

/**
 * forge script script/DeployRestakingRewardsDepositor.s.sol:DeployRestakingRewardsDepositor --rpc-url=$RPC_URL --private-key $PK
 */
contract DeployRestakingRewardsDepositor is DeployerHelper {
    PufferRestakingRewardsDepositor public restakingRewardsDepositor;

    bytes public encodedCalldata;

    function run() public {
        GenerateRestakingRewardsDepositorCalldata calldataGenerator = new GenerateRestakingRewardsDepositorCalldata();

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

        PufferRestakingRewardsDepositor restakingRewardsDepositorImpl = new PufferRestakingRewardsDepositor({
            vault: _getPufferVault(),
            weth: _getWETH(),
            treasury: _getTreasury()
        });

        restakingRewardsDepositor = PufferRestakingRewardsDepositor(
            (
                payable(
                    new ERC1967Proxy{ salt: bytes32("restakingRewardsDepositor") }(
                        address(restakingRewardsDepositorImpl),
                        abi.encodeCall(
                            PufferRestakingRewardsDepositor.initialize,
                            (address(_getAccessManager()), operatorsAddresses)
                        )
                    )
                )
            )
        );

        vm.label(address(restakingRewardsDepositor), "PufferRestakingRewardsDepositorProxy");
        vm.label(address(restakingRewardsDepositorImpl), "PufferRestakingRewardsDepositorImplementation");

        encodedCalldata = calldataGenerator.run({ restakingRewardsDepositorProxy: address(restakingRewardsDepositor) });

        console.log("Queue from Timelock -> AccessManager", _getAccessManager());
        console.logBytes(encodedCalldata);

        if (block.chainid == holesky) {
            (bool success,) = address(_getAccessManager()).call(encodedCalldata);
            require(success, "AccessManager.call failed");
        }

        vm.stopBroadcast();
    }
}
