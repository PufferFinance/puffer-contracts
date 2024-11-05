// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { IValidatorTicket } from "../../src/interface/IValidatorTicket.sol";
import { PufferOracle } from "../../src/PufferOracle.sol";
import { PufferOracleV2 } from "../../src/PufferOracleV2.sol";
import { IPufferVault } from "../../src/interface/IPufferVault.sol";
import { PufferVaultV2 } from "../../src/PufferVaultV2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { PUBLIC_ROLE, ROLE_ID_PUFETH_BURNER, ROLE_ID_VAULT_WITHDRAWER } from "../../script/Roles.sol";
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
        burnerSelectors[0] = PufferVaultV2.burn.selector;
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

    function test_purchaseValidatorTicketWithPufETH() public {
        uint256 vtAmount = 10 ether;
        address recipient = actors[0];

        uint256 vtPrice = pufferOracle.getValidatorTicketPrice();
        uint256 requiredETH = vtAmount.mulDiv(vtPrice, 1 ether, Math.Rounding.Ceil);

        uint256 expectedPufEthUsed = pufferVault.convertToSharesUp(requiredETH);

        _givePufETH(expectedPufEthUsed, recipient);

        vm.startPrank(recipient);
        pufferVault.approve(address(validatorTicket), expectedPufEthUsed);

        uint256 pufEthUsed = validatorTicket.purchaseValidatorTicketWithPufETH(recipient, vtAmount);
        vm.stopPrank();

        assertEq(pufEthUsed, expectedPufEthUsed, "PufETH used should match expected");
        assertEq(validatorTicket.balanceOf(recipient), vtAmount, "VT balance should match requested amount");
    }

    function test_purchaseValidatorTicketWithPufETH_exchangeRateChange() public {
        uint256 vtAmount = 10 ether;
        address recipient = actors[2];

        uint256 exchangeRate = pufferVault.convertToAssets(1 ether);
        assertEq(exchangeRate, 1 ether, "1:1 exchange rate");

        // Simulate + 10% increase in ETH
        deal(address(pufferVault), 1110 ether);
        exchangeRate = pufferVault.convertToAssets(1 ether);
        assertGt(exchangeRate, 1 ether, "Now exchange rate should be greater than 1");

        uint256 vtPrice = pufferOracle.getValidatorTicketPrice();
        uint256 requiredETH = vtAmount.mulDiv(vtPrice, 1 ether, Math.Rounding.Ceil);

        uint256 pufEthAmount = pufferVault.convertToSharesUp(requiredETH);

        _givePufETH(pufEthAmount, recipient);

        vm.startPrank(recipient);
        pufferVault.approve(address(validatorTicket), pufEthAmount);
        uint256 pufEthUsed = validatorTicket.purchaseValidatorTicketWithPufETH(recipient, vtAmount);
        vm.stopPrank();

        assertEq(pufEthUsed, pufEthAmount, "PufETH used should match expected");
        assertEq(validatorTicket.balanceOf(recipient), vtAmount, "VT balance should match requested amount");
    }

    function test_purchaseValidatorTicketWithPufETHAndPermit() public {
        uint256 vtAmount = 10 ether;
        address recipient = actors[2];

        uint256 vtPrice = pufferOracle.getValidatorTicketPrice();
        uint256 requiredETH = vtAmount * vtPrice / 1 ether;

        uint256 pufETHToETHExchangeRate = pufferVault.convertToAssets(1 ether);
        uint256 expectedPufEthUsed = (requiredETH * 1 ether) / pufETHToETHExchangeRate;

        _givePufETH(expectedPufEthUsed, recipient);

        // Create a permit
        Permit memory permit = _signPermit(
            _testTemps("charlie", address(validatorTicket), expectedPufEthUsed, block.timestamp),
            pufferVault.DOMAIN_SEPARATOR()
        );

        vm.prank(recipient);
        uint256 pufEthUsed = validatorTicket.purchaseValidatorTicketWithPufETHAndPermit(recipient, vtAmount, permit);

        assertEq(pufEthUsed, expectedPufEthUsed, "PufETH used should match expected");
        assertEq(validatorTicket.balanceOf(recipient), vtAmount, "VT balance should match requested amount");
    }

    function _givePufETH(uint256 pufEthAmount, address recipient) internal {
        deal(address(pufferVault), recipient, pufEthAmount);
    }

    function _signPermit(bytes32 structHash, bytes32 domainSeparator) internal view returns (Permit memory permit) {
        // TODO: Implement signing logic here
        permit = Permit({ amount: 10 ether, deadline: block.timestamp + 1 hours, v: 27, r: bytes32(0), s: bytes32(0) });
    }

    function test_funds_splitting_with_pufETH() public {
        uint256 vtAmount = 2000 ether; // Want to mint 2000 VTs
        address recipient = actors[0];
        address treasury = validatorTicket.TREASURY();
        address operationsMultisig = validatorTicket.OPERATIONS_MULTISIG();

        uint256 vtPrice = pufferOracle.getValidatorTicketPrice();
        uint256 requiredETH = vtAmount.mulDiv(vtPrice, 1 ether, Math.Rounding.Ceil);

        uint256 pufEthAmount = pufferVault.convertToSharesUp(requiredETH);

        _givePufETH(pufEthAmount, recipient);

        uint256 initialTreasuryBalance = pufferVault.balanceOf(treasury);
        uint256 initialOpsMultisigBalance = pufferVault.balanceOf(operationsMultisig);
        uint256 initialBurnedAmount = pufferVault.totalSupply();

        vm.startPrank(recipient);
        pufferVault.approve(address(validatorTicket), pufEthAmount);
        uint256 pufEthUsed = validatorTicket.purchaseValidatorTicketWithPufETH(recipient, vtAmount);
        vm.stopPrank();

        assertEq(pufEthUsed, pufEthAmount, "PufETH used should match expected");
        assertEq(validatorTicket.balanceOf(recipient), vtAmount, "Should mint requested VTs");

        uint256 expectedTreasuryAmount = pufEthAmount.mulDiv(500, 10000, Math.Rounding.Ceil); // 5% to treasury
        uint256 expectedGuardianAmount = pufEthAmount.mulDiv(50, 10000, Math.Rounding.Ceil); // 0.5% to guardians
        uint256 expectedBurnAmount = pufEthAmount - expectedTreasuryAmount - expectedGuardianAmount;

        assertEq(
            pufferVault.balanceOf(treasury) - initialTreasuryBalance,
            expectedTreasuryAmount,
            "Treasury should receive 5% of pufETH"
        );
        assertEq(
            pufferVault.balanceOf(operationsMultisig) - initialOpsMultisigBalance,
            expectedGuardianAmount,
            "Operations Multisig should receive 0.5% of pufETH"
        );
        assertEq(
            initialBurnedAmount - pufferVault.totalSupply(), expectedBurnAmount, "Remaining pufETH should be burned"
        );
    }

    function test_revert_zero_recipient() public {
        uint256 vtAmount = 10 ether;

        vm.expectRevert(IValidatorTicket.RecipientIsZeroAddress.selector);
        validatorTicket.purchaseValidatorTicketWithPufETH(address(0), vtAmount);

        Permit memory permit = _signPermit(
            _testTemps("charlie", address(validatorTicket), vtAmount, block.timestamp), pufferVault.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(IValidatorTicket.RecipientIsZeroAddress.selector);
        validatorTicket.purchaseValidatorTicketWithPufETHAndPermit(address(0), vtAmount, permit);
    }
}
