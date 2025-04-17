// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { DeployerHelper } from "../../script/DeployerHelper.s.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { IStrategy } from "../../src/interface/Eigenlayer-Slashing/IStrategy.sol";
import { IDelegationManagerTypes } from "../../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { DeployRestakingOperator } from "../../script/DeployRestakingOperator.s.sol";
import { DeployPufferModuleImplementation } from "../../script/DeployPufferModuleImplementation.s.sol";
import { IDelegationManager } from "../../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { DeployPufferModuleManager } from "../../script/DeployPufferModuleManager.s.sol";
import { DeployRestakingOperatorController } from "../../script/DeployRestakingOperatorController.s.sol";
import { RestakingOperatorController } from "../../src/RestakingOperatorController.sol";

contract PufferModuleManagerSlasherIntegrationTest is Test, DeployerHelper {
    PufferModuleManager public pufferModuleManager;
    address PUFFER_MODULE_0_HOLESKY = 0x9017a172578458E1204691D6E1dB92ca61381655;
    address EIGENPOD_0_HOLESKY = 0xeD9B08B8958B89E7A9008CAc0937E46F73Bf8f52;
    address RESTAKING_OPERATOR_0_HOLESKY = 0x57b6FdEF3A23B81547df68F44e5524b987755c99;
    bytes32 PUFFER_MODULE_0_NAME = bytes32("PUFFER_MODULE_0");

    DeployPufferModuleManager deployPufferModuleManager;
    DeployPufferModuleImplementation deployPufferModule;
    DeployRestakingOperator deployRestakingOperator;

    uint32 START_BLOCK = 2994229; // Dec-23-2024 09:43:00 AM +UTC

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("holesky"), START_BLOCK);

        // I want to use the deployment scripts to deploy the contracts in tests.
        deployPufferModuleManager = new DeployPufferModuleManager();
        deployPufferModule = new DeployPufferModuleImplementation();
        deployRestakingOperator = new DeployRestakingOperator();

        // To do that, we must allow cheatcodes for those scripts
        vm.allowCheatcodes(address(deployPufferModuleManager));
        vm.allowCheatcodes(address(deployPufferModule));
        vm.allowCheatcodes(address(deployRestakingOperator));

        deployPufferModuleManager.deployPufferModuleManagerTests();
        deployPufferModule.deployPufferModuleTests();

        RestakingOperatorController reOpController =
            new DeployRestakingOperatorController().deployRestakingOperatorController();
        deployRestakingOperator.deployRestakingOperatorTests(address(reOpController));

        pufferModuleManager = PufferModuleManager(payable(_getPufferModuleManager()));
    }

    // Queue new withdrawals
    function test_new_queue_withdrawals() public {
        vm.startPrank(_getPaymaster());
        pufferModuleManager.callQueueWithdrawals(PUFFER_MODULE_0_NAME, 0.1 ether);
    }

    // New withdrawal flow
    function test_queue_and_claim_withdrawals() public {
        vm.startPrank(_getPaymaster());

        uint256 amount = 0.1 ether;
        pufferModuleManager.callQueueWithdrawals(PUFFER_MODULE_0_NAME, amount);

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(_getBeaconChainStrategy());

        uint256[] memory scaledShares = new uint256[](1);
        scaledShares[0] = amount;

        IDelegationManagerTypes.Withdrawal[] memory withdrawals = new IDelegationManagerTypes.Withdrawal[](1);
        withdrawals[0] = IDelegationManagerTypes.Withdrawal({
            staker: PUFFER_MODULE_0_HOLESKY,
            delegatedTo: RESTAKING_OPERATOR_0_HOLESKY,
            withdrawer: PUFFER_MODULE_0_HOLESKY,
            nonce: 42,
            startBlock: START_BLOCK,
            strategies: strategies,
            scaledShares: scaledShares
        });

        IERC20[][] memory tokens = new IERC20[][](1);
        tokens[0] = new IERC20[](1);
        tokens[0][0] = IERC20(_getBeaconChainStrategy());
        bool[] memory receiveAsTokens = new bool[](1);
        receiveAsTokens[0] = true;

        vm.roll(START_BLOCK + 50 + 1); // on Holesky its 50 blocks wait time, in Production it will be 14 days in blocks..

        pufferModuleManager.callCompleteQueuedWithdrawals(PUFFER_MODULE_0_NAME, withdrawals, tokens, receiveAsTokens);
    }
}
