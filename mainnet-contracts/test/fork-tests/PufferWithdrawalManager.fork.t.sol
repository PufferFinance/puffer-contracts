// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { DeployPufferWithdrawalManager } from "../../script/DeployPufferWithdrawalManager.s.sol";
import { PufferWithdrawalManager } from "../../src/PufferWithdrawalManager.sol";
import { IPufferWithdrawalManager } from "../../src/interface/IPufferWithdrawalManager.sol";

contract PufferWithdrawalManagerForkTest is MainnetForkTestHelper {
    address PUFFER_WHALE_1 = 0x47de9eE11976fA9280BE85ad959D8D341c087D23;
    address PUFFER_WHALE_2 = 0xCdd03A39690f1a8f63C05a90d114E9AC05A4C442;
    address PUFFER_WHALE_3 = 0xdc2389885C83CDA15d307d0528d3FE54700f2083;
    address PUFFER_WHALE_4 = 0x6910809C33D5a0C4C6e7dF6087019A6bEE9Dfc2c;
    address PUFFER_WHALE_5 = 0xFb1EF481a685436C86177082F5F39826600f566D;
    address PUFFER_WHALE_6 = 0x4CDf9Fc4b3C2f38Bc120Bc0af60ad5e8bB8f2cbe;
    address PUFFER_WHALE_7 = 0xAf3116348d1536FBe53E6Bc232646F0d3FCEc534;
    address PUFFER_WHALE_8 = 0x2D8560d3A82b46CcD75D508D9DF6E0f3dB590719;
    address PUFFER_WHALE_9 = 0x2faC5F25885B91a2C7Bb785bab84469e0CB45859;
    address PUFFER_WHALE_10 = 0xf5deEf25c379025F079e4Cd26eecE12363d6Bb61;

    address[] TOKEN_HOLDERS = [
        PUFFER_WHALE_1,
        PUFFER_WHALE_2,
        PUFFER_WHALE_3,
        PUFFER_WHALE_4,
        PUFFER_WHALE_5,
        PUFFER_WHALE_6,
        PUFFER_WHALE_7,
        PUFFER_WHALE_8,
        PUFFER_WHALE_9,
        PUFFER_WHALE_10
    ];

    PufferWithdrawalManager public withdrawalManager;

    function setUp() public virtual override {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20682408);

        // Setup contracts that are deployed to mainnet
        _setupLiveContracts();

        // Deploy PufferWithdrawalManager
        DeployPufferWithdrawalManager dplScript = new DeployPufferWithdrawalManager();
        dplScript.run();

        withdrawalManager = dplScript.withdrawalManager();

        vm.startPrank(_getTimelock());
        (bool success,) = address(_getAccessManager()).call(dplScript.encodedCalldata());
        require(success, "AccessManager.call failed");
        vm.stopPrank();
    }

    function test_balance() public view {
        assertGt(pufferVault.balanceOf(PUFFER_WHALE_1), 100 ether, "PUFFER_WHALE_1 has less than 100 ether");
    }

    /**
     * This is a fork fuzz test, but restricted to low runs to not spam the RPC node.
     * forge-config: default.fuzz.runs = 3
     * forge-config: default.fuzz.show-logs = true
     * forge-config: ci.fuzz.runs = 3
     */
    function test_withdraw(uint256) public {
        assertEq(pufferVault.totalAssets(), 520332641191616015099456, "total assets");

        // Create an array to store withdrawal amounts
        uint256[] memory withdrawalAmounts = new uint256[](10);
        uint256 pufETHToETHExchangeRate = pufferVault.convertToAssets(1 ether);

        uint256 totalPayoutAmount = 0;

        // Users request withdrawals, we record the exchange rate (1:1)
        for (uint256 i = 0; i < 10; i++) {
            uint256 withdrawalAmount = vm.randomUint(1 ether, 500 ether); // kinda random value

            withdrawalAmounts[i] = withdrawalAmount * pufETHToETHExchangeRate / 1 ether;
            totalPayoutAmount += withdrawalAmounts[i];

            address actor = TOKEN_HOLDERS[i % TOKEN_HOLDERS.length];

            deal(address(_WETH), actor, 0); // set their WETH balance to 0 for easier accounting at the end of the test

            vm.startPrank(actor);
            pufferVault.approve(address(withdrawalManager), withdrawalAmount);
            withdrawalManager.requestWithdrawal(uint128(withdrawalAmount), actor);
            vm.stopPrank();
        }

        assertEq(pufferVault.totalAssets(), 520332641191616015099456, "total assets doesn't change");

        vm.startPrank(_getPaymaster());
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        // Finalize withdrawals transfers ETH from the Vault to the WithdrawalManager
        assertEq(address(withdrawalManager).balance, totalPayoutAmount, "WithdrawalManager didn't receive ETH");

        assertEq(
            pufferVault.totalAssets(),
            (520332641191616015099456 - totalPayoutAmount),
            "total assets of the vault decreases"
        );

        // Complete withdrawals
        for (uint256 i = 0; i < 10; i++) {
            address actor = TOKEN_HOLDERS[i % TOKEN_HOLDERS.length];

            vm.startPrank(actor);

            vm.expectEmit(true, true, true, true);
            emit IPufferWithdrawalManager.WithdrawalCompleted(
                i + 10, withdrawalAmounts[i], pufETHToETHExchangeRate, actor
            );
            withdrawalManager.completeQueuedWithdrawal(i + 10);

            // the users did not get any yield from the VT sale, they got paid out using the original 1:1 exchange rate
            assertEq(_WETH.balanceOf(actor), withdrawalAmounts[i], "actor got paid in ETH");
        }

        assertEq(address(withdrawalManager).balance, 0, "WithdrawalManager paid out the ETH to users");
    }
}
