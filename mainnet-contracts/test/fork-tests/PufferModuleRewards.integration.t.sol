// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IntegrationTestHelper } from "../helpers/IntegrationTestHelper.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { PufferModule } from "../../src/PufferModule.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { ROLE_ID_OPERATIONS_PAYMASTER } from "../../script/Roles.sol";
import { IDelayedWithdrawalRouter } from "eigenlayer/interfaces/IDelayedWithdrawalRouter.sol";

contract PufferModuleRewardsIntegration is IntegrationTestHelper {
    IDelayedWithdrawalRouter EIGEN_DELAYED_WITHDRAWAL_ROUTER =
        IDelayedWithdrawalRouter(0x642c646053eaf2254f088e9019ACD73d9AE0FA32);

    function setUp() public {
        deployContractsHolesky();
    }

    // Fork test that withdraws the non restaking rewards from EigenPod -> PufferModule
    function test_collect_non_beacon_chain_eth() public {
        PufferModule module = PufferModule(payable(pufferProtocol.getModuleAddress(PUFFER_MODULE_0)));

        // Transfer 1 ETH to EigenPod
        vm.deal(address(this), 1 ether);
        (bool success,) = module.getEigenPod().call{ value: 1 ether }("");
        require(success, "failed to send eth");

        vm.prank(DAO);
        accessManager.grantRole(ROLE_ID_OPERATIONS_PAYMASTER, address(this), 0);

        // Queue withdrawal of 1 ETH
        moduleManager.callWithdrawNonBeaconChainETHBalanceWei(PUFFER_MODULE_0, 1 ether);

        assertEq(address(module).balance, 0, "module balance before claiming");

        vm.roll(block.number + 72000); // + 10 days in blocks

        // Claim the withdrawal directly for the PufferModule
        EIGEN_DELAYED_WITHDRAWAL_ROUTER.claimDelayedWithdrawals(address(module), 1);

        assertEq(address(module).balance, 1 ether, "module balance after claiming");
    }

    function test_noRestakingRewardsClaiming() public {
        // 1. Create a restaking module
        vm.startPrank(DAO);
        pufferProtocol.createPufferModule(bytes32("EIGEN_DA"));
        vm.stopPrank();

        // 2. Fetch the address of the module
        address payable createdModule = payable(pufferProtocol.getModuleAddress(bytes32("EIGEN_DA")));

        bytes memory pubKey = bytes.concat(abi.encodePacked(bytes32("mockPubKey")), bytes16(""));
        bytes memory signatureMock =
            hex"8aa088146c8c6ca6d8ad96648f20e791be7c449ce7035a6bd0a136b8c7b7867f730428af8d4a2b69658bfdade185d6110b938d7a59e98d905e922d53432e216dc88c3384157d74200d3f2de51d31737ce19098ff4d4f54f77f0175e23ac98da5";

        PufferModule module = PufferModule(createdModule);

        bytes32 depositDataRoot = getDepositData(pubKey, signatureMock, module.getWithdrawalCredentials());
        // Simulate callStake
        vm.startPrank(address(pufferProtocol));
        vm.deal(payable(module), 32 ether);
        module.callStake({ pubKey: pubKey, signature: signatureMock, depositDataRoot: depositDataRoot });
        vm.stopPrank();

        // 3. Simulate rewards to EigenPod
        // vm.deal(payable(module.getEigenPod()), 5 ether);

        // // 4. Queue the withdrawal
        // vm.startPrank(address(pufferProtocol.PUFFER_MODULE_MANAGER()));
        // module.queueWithdrawals(1 ether);

        // Try claiming right away, it doesn't revert, but the amount claimed is 0
        // module.queueWithdrawals();

        // 5. Fast forward 10 days into the future
        // vm.roll(18_794_775);

        // Assert that we had 0 before claiming
        // assertEq(0, createdModule.balance, "zero balance before");

        // // 6. Claim
        // module.claimNonRestakingRewards();

        // // Assert that we got ETH from our router
        // assertEq(5 ether, createdModule.balance, "5 ether balance after claiming");
    }
}
