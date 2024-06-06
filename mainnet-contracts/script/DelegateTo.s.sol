// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";

/**
 * @title Delegates from the `--private-key` (msg.sender) to the specified Restaking Operator
 * @dev Example on how to run the script
 *
 * The script assumes that the `restakingOperator` has no delegation approver.
 *
 *
 *      forge script script/DelegateTo.s.sol:DelegateTo --rpc-url=$RPC_URL --broadcast --sig "run(address)" $RESTAKING -vvvv --private-key $PK
 */
contract DelegateTo is Script {
    /**
     * @param restakingOperator Is the address of the restaking operator
     */
    function run(address restakingOperator) external {
        ISignatureUtils.SignatureWithExpiry memory signatureWithExpiry;

        IDelegationManager(_getAddress()).delegateTo(restakingOperator, signatureWithExpiry, bytes32(0));
    }

    function _getAddress() internal view returns (address) {
        // Holesky
        if (block.chainid == 17000) {
            return 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
        }

        // Mainnet
        if (block.chainid == 1) {
            return 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
        }

        revert("ChainId not supported");
    }
}
