pragma solidity ^0.8.0;

import { CryticERC4626PropertyTests } from "@crytic/contracts/ERC4626/ERC4626PropertyTests.sol";
import { PufferVaultV2 } from "../PufferVaultV2.sol";
import { WETH9 } from "../../test/mocks/WETH9.sol";
import { stETHMock } from "../../test/mocks/stETHMock.sol";
import { MockPufferOracle } from "../../test/mocks/MockPufferOracle.sol";
import { LidoWithdrawalQueueMock } from "../../test/mocks/LidoWithdrawalQueueMock.sol";

contract EchidnaPufferVaultV2 is CryticERC4626PropertyTests {
    constructor() {
        WETH9 weth = new WETH9();
        stETHMock stETH = new stETHMock();
        MockPufferOracle oracle = new MockPufferOracle();
        LidoWithdrawalQueueMock lido = new LidoWithdrawalQueueMock();
        PufferVaultV2 vault = new PufferVaultV2(stETH, weth, lido, oracle);
        initialize(address(vault), address(weth), false);
    }
}
