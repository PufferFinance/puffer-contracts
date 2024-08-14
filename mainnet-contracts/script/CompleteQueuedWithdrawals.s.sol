// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { IStrategy } from "eigenlayer/interfaces/IStrategy.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";

struct ScriptParameters {
    address pufferModuleManager;
    address pufferModule;
    bytes32 moduleName;
    address[] delegatedTo;
    uint256[] nonces;
    uint32[] startBlocks;
    uint256[] sharesToWithdraw;
    bool[] receiveAsTokens;
}

/**
 * @dev Example on how to run the script
 *
 *      Holesky Example CompleteQueuedWithdrawals
 *      https://holesky.etherscan.io/tx/0x6b77f85ba3024670499d74d3d900596e9b9d5231ed3f8b2506d68f6ec6673b09
 *
 *      Add --broadcast to send the transaction
 *
 *      forge script script/CompleteQueuedWithdrawals.s.sol:CompleteQueuedWithdrawals --rpc-url=$HOLESKY_RPC_URL --sig "run((address,address,bytes32,address[],uint256[],uint32[],uint256[],bool[]))" "(0xe4695ab93163F91665Ce5b96527408336f070a71,0x0B0456ec773B7D89C9deCc38b682F98556CF9862,0x5055464645525f4d4f44554c455f300000000000000000000000000000000000,[0xe2c2dc296a0bFF351F6bC3e98D37ea798e393e56],[2],[1422237],[31993365640000000000],[false])" -vvvv --private-key=$PUFFER_SHARED_PK
 */
contract CompleteQueuedWithdrawals is Script {
    address public BEACON_CHAIN_STRATEGY = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;

    function run(ScriptParameters memory params) external {
        IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](params.nonces.length);

        // Withdrawal data can be fetched from the transaction logs, for example:
        // cast run 0x3fecf92f659089b796922a11271e713bc97040f1a21b2671274577d4b294c5b9 --rpc-url=$HOLESKY_RPC_URL --verbose

        // Get validator fields and proofs
        for (uint256 i = 0; i < params.nonces.length; ++i) {
            uint256[] memory shares = new uint256[](1);
            shares[0] = params.sharesToWithdraw[i];

            IStrategy[] memory strategies = new IStrategy[](1);
            strategies[0] = IStrategy(BEACON_CHAIN_STRATEGY);

            withdrawals[i] = IDelegationManager.Withdrawal({
                staker: params.pufferModule,
                delegatedTo: params.delegatedTo[i],
                withdrawer: params.pufferModule,
                nonce: params.nonces[i],
                startBlock: params.startBlocks[i],
                strategies: strategies,
                shares: shares
            });
        }

        IERC20[] memory t = new IERC20[](1);
        t[0] = IERC20(BEACON_CHAIN_STRATEGY);

        IERC20[][] memory tokens = new IERC20[][](1);
        tokens[0] = t;
        uint256[] memory middlewareTimesIndexes = new uint256[](1); // 0

        vm.startBroadcast();
        PufferModuleManager(payable(params.pufferModuleManager)).callCompleteQueuedWithdrawals({
            moduleName: params.moduleName,
            withdrawals: withdrawals,
            tokens: tokens,
            middlewareTimesIndexes: middlewareTimesIndexes,
            receiveAsTokens: params.receiveAsTokens
        });
    }
}
