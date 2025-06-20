// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { IValidatorTicket } from "../../src/interface/IValidatorTicket.sol";
import { PufferOracle } from "../../src/PufferOracle.sol";
import { PufferOracleV2 } from "../../src/PufferOracleV2.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { PUBLIC_ROLE, ROLE_ID_PUFETH_BURNER } from "../../script/Roles.sol";
import { Permit } from "../../src/structs/Permit.sol";
import "forge-std/console.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
/**
 * @dev This test is for the ValidatorTicket smart contract with `src/PufferOracle.sol`
 */

contract ValidatorTicketTest is UnitTestHelper {
    using ECDSA for bytes32;
    using Address for address;
    using Address for address payable;
    using Math for uint256;

    address[] public actors;

    function setUp() public override {
        // Just call the parent setUp()
        super.setUp();

        //@todo Note:
        // In this unit tests, we are using the simplified PufferOracle smart contract
        // ValidatorTicket uses .getValidatorTicketPrice() to get the price of the VT from the oracle
        // In the initial deployment, the PufferOracle will supply that information
        pufferOracle = PufferOracleV2(address(new PufferOracle(address(accessManager))));
        _skipDefaultFuzzAddresses();
        // Grant the ValidatorTicket contract the ROLE_ID_PUFETH_BURNER role
        vm.startPrank(_broadcaster);
        vm.label(address(validatorTicket), "ValidatorTicket");
        console.log("validatorTicket", address(validatorTicket));

        bytes4[] memory burnerSelectors = new bytes4[](1);
        burnerSelectors[0] = PufferVaultV5.burn.selector;
        accessManager.setTargetFunctionRole(address(pufferVault), burnerSelectors, ROLE_ID_PUFETH_BURNER);

        bytes4[] memory validatorTicketPublicSelectors = new bytes4[](3);
        validatorTicketPublicSelectors[0] = IValidatorTicket.purchaseValidatorTicketWithPufETH.selector;
        validatorTicketPublicSelectors[1] = IValidatorTicket.purchaseValidatorTicketWithPufETHAndPermit.selector;

        accessManager.setTargetFunctionRole(address(validatorTicket), validatorTicketPublicSelectors, PUBLIC_ROLE);
        accessManager.grantRole(ROLE_ID_PUFETH_BURNER, address(validatorTicket), 0);
        vm.stopPrank();

        // Initialize actors
        actors.push(alice);
        actors.push(bob);
        actors.push(charlie);
        actors.push(dianna);
        actors.push(ema);
    }

    function test_setup() public view {
        assertEq(validatorTicket.name(), "Puffer Validator Ticket");
        assertEq(validatorTicket.symbol(), "VT");
        assertEq(validatorTicket.getProtocolFeeRate(), 500, "protocol fee rate"); // 5%
        assertTrue(address(validatorTicket.PUFFER_ORACLE()) != address(0), "oracle");
        assertTrue(validatorTicket.GUARDIAN_MODULE() != address(0), "guardians");
        assertTrue(validatorTicket.PUFFER_VAULT() != address(0), "vault");
    }

    function test_set_guardians_fee_rate() public {
        assertEq(validatorTicket.getGuardiansFeeRate(), 50, "initial guardians fee rate");

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IValidatorTicket.GuardiansFeeChanged(50, 1000);
        validatorTicket.setGuardiansFeeRate(1000); // 10%

        assertEq(validatorTicket.getGuardiansFeeRate(), 1000, "new guardians fee rate");
    }

    function test_zero_protocol_fee_rate() public {
        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IValidatorTicket.ProtocolFeeChanged(500, 0); // 5% -> %0
        validatorTicket.setProtocolFeeRate(0);
        vm.stopPrank(); // because this test is reused in other test
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_overflow_protocol_fee_rate() public {
        vm.startPrank(DAO);
        vm.expectRevert();
        validatorTicket.setProtocolFeeRate(type(uint128).max + 5);
    }

    function test_change_protocol_fee_rate() public {
        vm.startPrank(DAO);

        uint256 newFeeRate = 800; // 8%

        vm.expectEmit(true, true, true, true);
        emit IValidatorTicket.ProtocolFeeChanged(500, newFeeRate);
        validatorTicket.setProtocolFeeRate(newFeeRate);

        assertEq(validatorTicket.getProtocolFeeRate(), newFeeRate, "updated");
    }

    function _givePufETH(uint256 pufEthAmount, address recipient) internal {
        deal(address(pufferVault), recipient, pufEthAmount);
    }
}
