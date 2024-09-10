// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { PUFI } from "../../src/PUFI.sol";

contract PUFITest is Test { 
    function test_constructor() public {
        PUFI pufi = new PUFI();
        assertEq(pufi.name(), "PUFI");
        assertEq(pufi.symbol(), "PUFI");
    }
}