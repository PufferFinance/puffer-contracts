// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PufferWithdrawalManager } from "../src/PufferWithdrawalManager.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IWETH } from "../src/interface/Other/IWETH.sol";
import { PufferVaultV3 } from "../src/PufferVaultV3.sol";
import { Generate2StepWithdrawalsCalldata } from "./AccessManagerMigrations/04_Generate2StepWithdrawalsCalldata.s.sol";

/**
 * forge script script/DeployPufferWithdrawalManager.s.sol:DeployPufferWithdrawalManager --rpc-url=$RPC_URL --private-key $PK
 */
contract DeployPufferWithdrawalManager is DeployerHelper {
    PufferWithdrawalManager public withdrawalManager;
    bytes public encodedCalldata;

    uint256 public BATCH_SIZE = 10;

    function run() public {
        Generate2StepWithdrawalsCalldata calldataGenerator = new Generate2StepWithdrawalsCalldata();

        vm.startBroadcast();

        PufferWithdrawalManager withdrawalManagerImpl =
            ((new PufferWithdrawalManager(BATCH_SIZE, PufferVaultV3(payable(_getPufferVault())), IWETH(_getWETH()))));

        withdrawalManager = PufferWithdrawalManager(
            (
                payable(
                    new ERC1967Proxy{ salt: bytes32("PufferWithdrawalManager") }(
                        address(withdrawalManagerImpl),
                        abi.encodeCall(PufferWithdrawalManager.initialize, address(_getAccessManager()))
                    )
                )
            )
        );

        vm.label(address(withdrawalManager), "PufferWithdrawalManagerProxy");
        vm.label(address(withdrawalManagerImpl), "PufferWithdrawalManagerImplementation");

        encodedCalldata = calldataGenerator.run({
            pufferVaultProxy: _getPufferVault(),
            withdrawalManagerProxy: address(withdrawalManager),
            paymaster: _getPaymaster(),
            withdrawalFinalizer: _getOPSMultisig(),
            pufferProtocolProxy: _getPufferProtocol()
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
