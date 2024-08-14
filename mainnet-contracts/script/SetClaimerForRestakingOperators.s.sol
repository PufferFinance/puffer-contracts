// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";

// forge script script/SetClaimerForRestakingOperators.s.sol:SetClaimerForRestakingOperators --rpc-url=$RPC_URL --private-key $PK

contract SetClaimerForRestakingOperators is BaseScript {
    address PufferModuleManagerAddress = 0x20377c306451140119C9967Ba6D0158a05b4eD07;
    address ACCESS_MANAGER = 0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e;
    address[] restakingOperators = [
        0x00FC6cAA942BF29d43739Cd949E2eddcf6E8d6F2,
        0xd51C6A2702d14e48389bC843279502E8E69F5859,
        0x9d24feA37ABC3481dd6C1a3DaBA55Bb8f1CB3D0A,
        0x501808A186CC1edc95C9F5722db76B4470e0B12a,
        0x7f08C09553DB44c826a323197612E6f8693F7FB1,
        0x557a6e478d2Ea61F0A27BAaA7E96CF3920DAb4B9
    ];
    address CLAIMER = 0x351bCcbAD23B19ACC73236d8671934e8b34A41aC;

    function run() public broadcast {
        require(block.chainid == 17000, "This script is only for Puffer Holesky testnet");

        for (uint256 i = 0; i < restakingOperators.length; i++) {
            PufferModuleManager(payable(PufferModuleManagerAddress)).callSetClaimerFor(restakingOperators[i], CLAIMER);
        }
    }
}
