// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelper } from "../helpers/TestHelper.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { IValidatorTicket } from "../../src/interface/IValidatorTicket.sol";
import { PufferOracle } from "../../src/PufferOracle.sol";
import { PufferOracleV2 } from "../../src/PufferOracleV2.sol";

/**
 * @dev This test is for the ValidatorTicket smart contract with `src/PufferOracle.sol`
 */
contract ValidatorTicketTest is TestHelper {
    using ECDSA for bytes32;
    using Address for address;
    using Address for address payable;

    function setUp() public override {
        // Just call the parent setUp()
        super.setUp();

        //@todo Note:
        // In this unit tests, we are using the simplified PufferOracle smart contract
        // ValidatorTicket uses .getValidatorTicketPrice() to get the price of the VT from the oracle
        // In the initial deployment, the PufferOracle will supply that information
        pufferOracle = PufferOracleV2(address(new PufferOracle(address(accessManager))));
        _skipDefaultFuzzAddresses();
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

    function test_funds_splitting() public {
        uint256 vtPrice = pufferOracle.getValidatorTicketPrice();

        uint256 amount = vtPrice * 2000; // 20000 VTs is 20 ETH
        vm.deal(address(this), amount);

        address treasury = validatorTicket.TREASURY();

        assertEq(validatorTicket.balanceOf(address(this)), 0, "should start with 0");
        assertEq(treasury.balance, 0, "treasury balance should start with 0");
        assertEq(address(guardianModule).balance, 0, "guardian balance should start with 0");

        validatorTicket.purchaseValidatorTicket{ value: amount }(address(this));

        // 0.5% from 20 ETH is 0.1 ETH
        assertEq(address(guardianModule).balance, 0.1 ether, "guardians balance");
        // 5% from 20 ETH is 1 ETH
        assertEq(treasury.balance, 1 ether, "treasury should get 1 ETH for 100 VTs");
    }

    function test_non_whole_number_purchase() public {
        uint256 vtPrice = pufferOracle.getValidatorTicketPrice();

        uint256 amount = 5.123 ether;
        uint256 expectedTotal = (amount * 1 ether / vtPrice);

        vm.deal(address(this), amount);
        uint256 mintedAmount = validatorTicket.purchaseValidatorTicket{ value: amount }(address(this));

        assertEq(validatorTicket.balanceOf(address(this)), expectedTotal, "VT balance");
        assertEq(mintedAmount, expectedTotal, "minted amount");
    }

    function test_zero_protocol_fee_rate() public {
        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IValidatorTicket.ProtocolFeeChanged(500, 0); // 5% -> %0
        validatorTicket.setProtocolFeeRate(0);
        vm.stopPrank(); // because this test is reused in other test
    }

    function test_split_funds_no_protocol_fee_rate() public {
        test_zero_protocol_fee_rate();

        uint256 vtPrice = pufferOracle.getValidatorTicketPrice();
        uint256 amount = vtPrice * 2000; // 20000 VTs is 20 ETH
        vm.deal(address(this), amount);

        vm.expectEmit(true, true, true, true);
        emit IValidatorTicket.DispersedETH(0, 0.1 ether, 19.9 ether);
        validatorTicket.purchaseValidatorTicket{ value: amount }(address(this));

        // 0.5% from 20 ETH is 0.1 ETH
        assertEq(address(guardianModule).balance, 0.1 ether, "guardians balance");
        assertEq(address(validatorTicket).balance, 0, "treasury should get 0 ETH");
    }

    function test_zero_vt_purchase() public {
        // No operation tx, nothing happens but doesn't revert
        vm.expectEmit(true, true, true, true);
        emit IValidatorTicket.DispersedETH(0, 0, 0);
        validatorTicket.purchaseValidatorTicket{ value: 0 }(address(this));
    }

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
}
