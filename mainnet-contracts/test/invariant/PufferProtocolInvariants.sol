// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferProtocolHandler } from "../handlers/PufferProtocolHandler.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";

contract PufferProtocolInvariants is UnitTestHelper {
    PufferProtocolHandler handler;

    function setUp() public override {
        super.setUp();

        handler = new PufferProtocolHandler(
            this, pufferVault, address(stETH), pufferProtocol, guardiansEnclavePks, _broadcaster
        );

        // Set handler as a target contract for invariant test
        targetContract(address(handler));
    }

    // PufferPool's ETH balance can only grow, unless it is `withdraw`
    function invariant_pufferVaultAssetsCanOnlyGoUp() public view {
        if (handler.ethLeavingThePool()) {
            assertLe(pufferVault.totalAssets(), handler.previousBalance(), "balance should be smaller");
        } else {
            assertGe(pufferVault.totalAssets(), handler.previousBalance(), "balance should go up");
        }
    }

    // Make sure that the pufETH doesn't disappear
    function invariant_pufferProtocolBond() public view {
        // Validate against ghost variable
        uint256 pufETHinProtocol = pufferVault.balanceOf(address(pufferProtocol));
        assertEq(handler.ghost_pufETH_bond_amount(), pufETHinProtocol, "missing bond from the protocol");

        // Validate by calculating eth
        uint256 ethAmount = pufferVault.convertToAssets(pufETHinProtocol);
        uint256 originalETHAmountDeposited = (handler.ghost_validators() * 1 ether);

        // If the eth amount is lower than the original eth deposited, it is because of the rounding down (calculation for when we pay out users)
        if (ethAmount < originalETHAmountDeposited) {
            assertApproxEqAbs(
                ethAmount,
                originalETHAmountDeposited,
                2, // 2 wei of difference is acceptable
                "bond should be worth more than the number of validators depositing"
            );
        } else {
            assertGe(
                ethAmount,
                originalETHAmountDeposited,
                "bond should be worth more than the number of validators depositing"
            );
        }
    }

    // pufETH should always be worth more than ETH
    function invariant_pufEthToETHRate() public view {
        // Exchange rate should always be bigger than 1:1, we are not supposed to be losing anything with this setup
        assertGe(pufferVault.convertToAssets(1 ether), 1 ether);
    }

    // 1 ETH converted to pufETH and then back to ETH should always equal 1 ETH
    function invariant_exchange_rate() public view {
        uint256 sharesAmount = pufferVault.convertToShares(1 ether);
        uint256 assetsAmount = pufferVault.convertToAssets(sharesAmount);

        // 2 wei of difference is acceptable (rounding)
        assertApproxEqAbs(assetsAmount, 1 ether, 2, "exchange rate is bad");
    }

    // if we set `fail_on_revert=true` in foundry.toml it doesn't work for some reason.abi
    // uncomment this test to show reverts from the handler
    function invariant_printError() public view {
        assertFalse(handler.printError(), "error should be false");
    }

    // Prints out he calls summary of the handler
    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
