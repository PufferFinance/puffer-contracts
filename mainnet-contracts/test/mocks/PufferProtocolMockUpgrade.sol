// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { GuardianModule } from "../../src/GuardianModule.sol";
import { PufferVaultV2 } from "../../src/PufferVaultV2.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { IPufferOracleV2 } from "../../src/interface/IPufferOracleV2.sol";
import { PufferNoRestakingValidator } from "../../src/PufferNoRestakingValidator.sol";

contract PufferProtocolMockUpgrade is PufferProtocol {
    function returnSomething() external pure returns (uint256) {
        return 1337;
    }

    // Addresses can't be 0, you get weird compilation error
    constructor(address beacon)
        PufferProtocol(
            PufferVaultV2(payable(address(1))),
            GuardianModule(payable(address(1))),
            address(1),
            ValidatorTicket(address(1)),
            IPufferOracleV2(address(1)),
            address(1),
            PufferNoRestakingValidator(payable(address(1)))
        )
    { }
}
