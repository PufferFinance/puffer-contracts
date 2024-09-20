// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { DeployPufferWithdrawalManager } from "../../script/DeployPufferWithdrawalManager.s.sol";
import { PufferWithdrawalManager } from "../../src/PufferWithdrawalManager.sol";
import { IPufferWithdrawalManager } from "../../src/interface/IPufferWithdrawalManager.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { PufferWithdrawalManagerTests } from "../mocks/PufferWithdrawalManagerTests.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";
import { PufferVaultV3 } from "../../src/PufferVaultV3.sol";
import { PufferOracle } from "../../src/PufferOracle.sol";

contract PufferWithdrawalManagerForkTest is MainnetForkTestHelper {
    address PUFFER_WHALE_1 = 0x176F3DAb24a159341c0509bB36B833E7fdd0a132;
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

    uint256 TOTAL_ASSETS = 520332641191616015099456;

    PufferWithdrawalManager public withdrawalManager;
    uint256 public batchSize;

    function setUp() public virtual override {
        vm.label(PUFFER_WHALE_1, "PUFFER_WHALE_1");
        vm.label(PUFFER_WHALE_2, "PUFFER_WHALE_2");
        vm.label(PUFFER_WHALE_3, "PUFFER_WHALE_3");
        vm.label(PUFFER_WHALE_4, "PUFFER_WHALE_4");
        vm.label(PUFFER_WHALE_5, "PUFFER_WHALE_5");
        vm.label(PUFFER_WHALE_6, "PUFFER_WHALE_6");
        vm.label(PUFFER_WHALE_7, "PUFFER_WHALE_7");
        vm.label(PUFFER_WHALE_8, "PUFFER_WHALE_8");
        vm.label(PUFFER_WHALE_9, "PUFFER_WHALE_9");
        vm.label(PUFFER_WHALE_10, "PUFFER_WHALE_10");

        vm.createSelectFork(vm.rpcUrl("mainnet"), 20682408);

        // Setup contracts that are deployed to mainnet
        _setupLiveContracts();

        // Deploy PufferWithdrawalManager
        DeployPufferWithdrawalManager dplScript = new DeployPufferWithdrawalManager();
        dplScript.run();

        withdrawalManager = dplScript.withdrawalManager();

        batchSize = withdrawalManager.BATCH_SIZE();

        vm.startPrank(_getTimelock());
        (bool success,) = address(_getAccessManager()).call(dplScript.encodedCalldata());
        require(success, "AccessManager.call failed");

        // Upgrade to the implementation that has the overridden `markWithdrawalRequest` modifier
        address newImpl = address(
            new PufferWithdrawalManagerTests(
                batchSize, PufferVaultV3(payable(address(pufferVault))), IWETH(address(_WETH))
            )
        );
        withdrawalManager.upgradeToAndCall(newImpl, "");
        vm.stopPrank();

        vm.startPrank(_getDAO());
        withdrawalManager.changeMaxWithdrawalAmount(type(uint256).max);
        vm.stopPrank();
    }

    function test_balance() public view {
        assertGt(pufferVault.balanceOf(PUFFER_WHALE_1), 100 ether, "PUFFER_WHALE_1 has less than 100 ether");
    }

    function test_one_user_one_batch() public {
        vm.startPrank(PUFFER_WHALE_1);

        uint256 pufETHToETHExchangeRate = pufferVault.convertToAssets(1 ether);
        uint256 withdrawalAmount = 1 ether;

        assertEq(pufETHToETHExchangeRate, 1.019124799735076818 ether, "pufETHToETHExchangeRate");

        deal(address(_WETH), PUFFER_WHALE_1, 0); // set their WETH balance to 0 for easier accounting at the end of the test

        // Users request withdrawals, we record the exchange rate (1:1)
        for (uint256 i = 0; i < batchSize; i++) {
            vm.startPrank(PUFFER_WHALE_1);
            pufferVault.approve(address(withdrawalManager), withdrawalAmount);
            withdrawalManager.requestWithdrawal(uint128(withdrawalAmount), PUFFER_WHALE_1);
            vm.stopPrank();
        }

        // Finalize the batch
        vm.startPrank(_getPaymaster());
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        // Complete the withdrawals
        vm.startPrank(PUFFER_WHALE_1);
        for (uint256 i = batchSize; i < batchSize * 2; i++) {
            withdrawalManager.completeQueuedWithdrawal(i);
        }

        // He withdrew 10 x 1 ETH, and received 10.19124799735076818 ETH
        assertEq(
            _WETH.balanceOf(PUFFER_WHALE_1),
            10.19124799735076818 ether,
            "PUFFER_WHALE_1 did receive the expected ETH amount"
        );
    }

    // We payout using the old exchange rate (user doesn't get any rewards from the VT sale)
    function test_one_user_one_batch_huge_vt_sale() public {
        vm.startPrank(PUFFER_WHALE_1);

        uint256 pufETHToETHExchangeRate = pufferVault.convertToAssets(1 ether);
        uint256 withdrawalAmount = 1 ether;

        assertEq(pufETHToETHExchangeRate, 1.019124799735076818 ether, "pufETHToETHExchangeRate");

        deal(address(_WETH), PUFFER_WHALE_1, 0); // set their WETH balance to 0 for easier accounting at the end of the test

        // Users request withdrawals, we record the exchange rate (1:1)
        for (uint256 i = 0; i < batchSize; i++) {
            vm.startPrank(PUFFER_WHALE_1);
            pufferVault.approve(address(withdrawalManager), withdrawalAmount);
            withdrawalManager.requestWithdrawal(uint128(withdrawalAmount), PUFFER_WHALE_1);
            vm.stopPrank();
        }

        // After the user has requested the withdrawals, there is a huge VT purchase
        vm.startPrank(0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8); // Binance hot wallet
        ValidatorTicket(_getValidatorTicket()).purchaseValidatorTicket{ value: 1000 ether }(address(5));
        vm.stopPrank();

        assertGt(pufferVault.totalAssets(), TOTAL_ASSETS, "total assets must be bigger now");
        assertGt(pufferVault.convertToAssets(1 ether), pufETHToETHExchangeRate, "the new exchange rate must be bigger");

        // Finalize the batch
        vm.startPrank(_getPaymaster());
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        // Complete the withdrawals
        vm.startPrank(PUFFER_WHALE_1);
        for (uint256 i = batchSize; i < batchSize * 2; i++) {
            withdrawalManager.completeQueuedWithdrawal(i);
        }

        // He withdrew 10 x 1 ETH, and received 10.19124799735076818 ETH
        assertEq(
            _WETH.balanceOf(PUFFER_WHALE_1),
            10.19124799735076818 ether,
            "PUFFER_WHALE_1 must receive the same ETH amount as he would have received if there was no VT sale"
        );
    }

    // Simulate a frontrunning attack where an attacker requests a withdrawal before a huge batch is finalized
    function test_frontRunningAttack() public {
        vm.startPrank(PUFFER_WHALE_1);

        uint256 pufETHToETHExchangeRate = pufferVault.convertToAssets(1 ether);
        assertEq(pufETHToETHExchangeRate, 1.019124799735076818 ether, "pufETHToETHExchangeRate");

        deal(address(_WETH), PUFFER_WHALE_2, 0); // set their WETH balance to 0 for easier accounting at the end of the test

        // Users request a withdrawal 10x1000 ETH ~ 23_577_600$
        for (uint256 i = 0; i < batchSize; i++) {
            vm.startPrank(PUFFER_WHALE_1);
            pufferVault.approve(address(withdrawalManager), 1000 ether);
            withdrawalManager.requestWithdrawal(uint128(1000 ether), PUFFER_WHALE_1);
            vm.stopPrank();
        }

        // After the user has requested the withdrawals, there is a huge VT purchase
        vm.startPrank(0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8); // Binance hot wallet
        assertEq(
            1000 ether / PufferOracle(_getPufferOracle()).getValidatorTicketPrice(), 404310, "Number of VTs purchased"
        );
        // ~40k VTs purchased
        ValidatorTicket(_getValidatorTicket()).purchaseValidatorTicket{ value: 1000 ether }(address(5));
        vm.stopPrank();

        assertGt(pufferVault.convertToAssets(1 ether), pufETHToETHExchangeRate, "the new exchange rate must be bigger");
        assertEq(pufferVault.convertToAssets(1 ether), 1.021034437149839315 ether, "new exchange rate");

        // This happens in the same block------- ----------------------------------------------------------------|
        // Puffer whale 2 is an attacker who requests a 500 ETH withdrawal before the finalization that is ~1M $ |
        vm.startPrank(PUFFER_WHALE_2); //                                                                        |
        uint256 attackerAmount = 500 ether; // The attacker would > 1M $ of capital for this attack              |
        pufferVault.approve(address(withdrawalManager), attackerAmount); //                                      |
        withdrawalManager.requestWithdrawal(uint128(attackerAmount), PUFFER_WHALE_2); //                         |
        //                                                                                                       |
        // Expected WETH amount before batch 1 is finalized (10x1000 ETH)                                        |
        uint256 expectedAttackerWETH = //                                                                        |
         (attackerAmount + 0.01 ether * (batchSize - 1)) * pufferVault.convertToAssets(1 ether) / 1 ether; //    |
        //                                                                                                       |
        // Finalize the batch                                                                                    |
        vm.startPrank(_getPaymaster()); //                                                                       |
        withdrawalManager.finalizeWithdrawals(1); //                                                             |
        vm.stopPrank(); //                                                                                       |
        // ------------------------------------------------------------------------------------------------------|

        // Whale 2 requests additional withdrawals so that we can finalize his batch as well.
        for (uint256 i = batchSize; i < batchSize * 2 - 1; i++) {
            vm.startPrank(PUFFER_WHALE_2);
            pufferVault.approve(address(withdrawalManager), 0.01 ether);
            withdrawalManager.requestWithdrawal(0.01 ether, PUFFER_WHALE_2);
        }

        // Complete the withdrawals for whale 1
        vm.startPrank(PUFFER_WHALE_1);
        for (uint256 i = batchSize; i < batchSize * 2; i++) {
            withdrawalManager.completeQueuedWithdrawal(i);
        }

        // Finalize the batch for whale 2
        vm.startPrank(_getPaymaster());
        withdrawalManager.finalizeWithdrawals(2);
        vm.stopPrank();

        // Complete the withdrawals for whale 2
        vm.startPrank(PUFFER_WHALE_2);
        for (uint256 i = batchSize * 2; i < batchSize * 3; i++) {
            withdrawalManager.completeQueuedWithdrawal(i);
        }

        // Attacker is in profit
        assertGt(
            _WETH.balanceOf(PUFFER_WHALE_2),
            expectedAttackerWETH,
            "PUFFER_WHALE_2 must receive the same ETH amount as he would have received if there was no VT sale"
        );

        assertEq(
            _WETH.balanceOf(PUFFER_WHALE_2),
            510.609115107709215955 ether,
            "PUFFER_WHALE_2 must receive the same ETH amount as he would have received if there was no VT sale"
        );

        assertEq(expectedAttackerWETH, 510.609111674263143038 ether, "Expected ETH amount");

        assertGt(
            510.609115107709215955 ether, // the amount received by whale 2
            expectedAttackerWETH,
            "PUFFER_WHALE_1 must receive the same ETH amount as he would have received if there was no VT sale"
        );

        // It is not worth for somebody to use 500 ETH to get 3433446072917 wei
        // The amount would be bigger if a bigger VT sale was made (but 1000 ETH is still a lot)
        assertEq(_WETH.balanceOf(PUFFER_WHALE_2) - expectedAttackerWETH, 3433446072917, "Attacker profit");
    }

    // We payout using the old exchange rate (user doesn't get any rewards from the VT sale)
    function test_one_user_one_huge_slashing() public {
        vm.startPrank(PUFFER_WHALE_1);

        uint256 pufETHToETHExchangeRate = pufferVault.convertToAssets(1 ether);
        uint256 withdrawalAmount = 1 ether;

        assertEq(pufETHToETHExchangeRate, 1.019124799735076818 ether, "pufETHToETHExchangeRate");

        deal(address(_WETH), PUFFER_WHALE_1, 0); // set their WETH balance to 0 for easier accounting at the end of the test

        // Users request withdrawals, we record the exchange rate (1:1)
        for (uint256 i = 0; i < batchSize; i++) {
            vm.startPrank(PUFFER_WHALE_1);
            pufferVault.approve(address(withdrawalManager), withdrawalAmount);
            withdrawalManager.requestWithdrawal(uint128(withdrawalAmount), PUFFER_WHALE_1);
            vm.stopPrank();
        }

        // Simulate huge slashing, major incident
        deal(address(pufferVault), 0);

        assertLt(pufferVault.totalAssets(), TOTAL_ASSETS, "total assets must be smaller now");
        assertLt(pufferVault.convertToAssets(1 ether), pufETHToETHExchangeRate, "the new exchange rate must be smaller");

        // Finalize the batch
        vm.startPrank(_getPaymaster());
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        // Complete the withdrawals
        vm.startPrank(PUFFER_WHALE_1);
        for (uint256 i = batchSize; i < batchSize * 2; i++) {
            withdrawalManager.completeQueuedWithdrawal(i);
        }

        // He withdrew 10 x 1 ETH, and received 9.38124713495630522 ETH
        assertEq(
            _WETH.balanceOf(PUFFER_WHALE_1),
            9.38124713495630522 ether,
            "PUFFER_WHALE_1 must receive the same ETH amount as he would have received if there was no VT sale"
        );
    }

    /**
     * This is a fork fuzz test, but restricted to low runs to not spam the RPC node.
     * forge-config: default.fuzz.runs = 3
     * forge-config: default.fuzz.show-logs = true
     * forge-config: ci.fuzz.runs = 3
     */
    function test_withdraw(uint256) public {
        assertEq(pufferVault.totalAssets(), TOTAL_ASSETS, "total assets");

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

        assertEq(pufferVault.totalAssets(), TOTAL_ASSETS, "total assets doesn't change");

        vm.startPrank(_getPaymaster());
        withdrawalManager.finalizeWithdrawals(1);
        vm.stopPrank();

        // Finalize withdrawals transfers ETH from the Vault to the WithdrawalManager
        assertEq(address(withdrawalManager).balance, totalPayoutAmount, "WithdrawalManager didn't receive ETH");

        assertEq(pufferVault.totalAssets(), (TOTAL_ASSETS - totalPayoutAmount), "total assets of the vault decreases");

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
