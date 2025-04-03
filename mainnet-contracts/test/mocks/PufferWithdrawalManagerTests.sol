// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferWithdrawalManager } from "../../src/PufferWithdrawalManager.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";

contract PufferWithdrawalManagerTests is PufferWithdrawalManager {
    constructor(uint256 batchSize, PufferVaultV5 pufferVault, IWETH weth)
        PufferWithdrawalManager(batchSize, pufferVault, weth)
    { }

    modifier oneWithdrawalRequestAllowed() override {
        _;
    }
}
