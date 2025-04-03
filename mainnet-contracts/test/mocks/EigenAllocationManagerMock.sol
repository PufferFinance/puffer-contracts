// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IAllocationManagerTypes } from "src/interface/Eigenlayer-Slashing/IAllocationManager.sol";

// New way of registering and de-registering operators to/from AVS
contract EigenAllocationManagerMock {
    function registerForOperatorSets(
        address operator,
        IAllocationManagerTypes.RegisterParams calldata registrationParams
    ) external { }

    function deregisterFromOperatorSets(IAllocationManagerTypes.DeregisterParams calldata params) external { }
}
