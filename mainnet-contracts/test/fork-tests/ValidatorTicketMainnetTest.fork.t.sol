// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { UpgradeValidatorTicket } from "../../script/UpgradeValidatorTicket.s.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { IValidatorTicket } from "../../src/interface/IValidatorTicket.sol";
import { PufferVaultV3 } from "../../src/PufferVaultV3.sol";
import { IPufferOracle } from "../../src/interface/IPufferOracle.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract ValidatorTicketMainnetTest is MainnetForkTestHelper {
    using Math for uint256;

    address[] TOKEN_HOLDERS = [alice, bob, charlie, dave, eve];

    ValidatorTicket public validatorTicket;
    uint256 public constant INITIAL_PROTOCOL_FEE = 200; // 2%
    uint256 public constant INITIAL_GUARDIANS_FEE = 50; // 0.5%

    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21120959);

        // Label accounts for better trace output
        for (uint256 i = 0; i < TOKEN_HOLDERS.length; i++) {
            string memory name = i == 0 ? "alice" : i == 1 ? "bob" : i == 2 ? "charlie" : i == 3 ? "dave" : "eve";
            vm.label(TOKEN_HOLDERS[i], name);
        }

        // Setup contracts that are deployed to mainnet
        _setupLiveContracts();

        // Deploy new implementation and get upgrade call data
        UpgradeValidatorTicket upgradeScript = new UpgradeValidatorTicket();
        upgradeScript.run();
        validatorTicket = upgradeScript.validatorTicket();
        bytes memory upgradeCallData = upgradeScript.upgradeCallData();
        bytes memory accessManagerCallData = upgradeScript.accessManagerCallData();

        // Upgrade validator ticket through timelock and execute access control changes
        vm.startPrank(_getTimelock());
        (bool success,) = address(validatorTicket).call(upgradeCallData);
        require(success, "Upgrade.call failed");
        (success,) = address(_getAccessManager()).call(accessManagerCallData);
        require(success, "AccessManager.call failed");
        vm.stopPrank();
    }

    function test_initial_state() public {
        assertEq(validatorTicket.name(), "Puffer Validator Ticket");
        assertEq(validatorTicket.symbol(), "VT");
        assertEq(validatorTicket.getProtocolFeeRate(), INITIAL_PROTOCOL_FEE);
        assertEq(validatorTicket.getGuardiansFeeRate(), INITIAL_GUARDIANS_FEE);
        assertTrue(address(validatorTicket.PUFFER_ORACLE()) != address(0));
        assertTrue(validatorTicket.GUARDIAN_MODULE() != address(0));
        assertTrue(validatorTicket.PUFFER_VAULT() != address(0));
        assertTrue(validatorTicket.TREASURY() != address(0));
        assertTrue(validatorTicket.OPERATIONS_MULTISIG() != address(0));
    }

    function test_purchase_validator_ticket_with_pufeth() public {
        uint256 vtAmount = 10 ether;
        address recipient = alice;

        uint256 vtPrice = IPufferOracle(address(validatorTicket.PUFFER_ORACLE())).getValidatorTicketPrice();
        uint256 requiredETH = vtAmount.mulDiv(vtPrice, 1 ether, Math.Rounding.Ceil);
        uint256 expectedPufEthUsed =
            PufferVaultV3(payable(validatorTicket.PUFFER_VAULT())).convertToSharesUp(requiredETH);

        // Give whale some pufETH
        deal(address(validatorTicket.PUFFER_VAULT()), recipient, expectedPufEthUsed * 2);

        vm.startPrank(recipient);
        IERC20(validatorTicket.PUFFER_VAULT()).approve(address(validatorTicket), expectedPufEthUsed);

        uint256 pufEthUsed = validatorTicket.purchaseValidatorTicketWithPufETH(recipient, vtAmount);
        vm.stopPrank();

        assertEq(pufEthUsed, expectedPufEthUsed, "PufETH used should match expected");
        assertEq(validatorTicket.balanceOf(recipient), vtAmount, "VT balance should match requested amount");
    }

    function test_funds_splitting_with_pufeth() public {
        uint256 vtAmount = 2000 ether;
        address recipient = dave;
        address treasury = validatorTicket.TREASURY();
        address operationsMultisig = validatorTicket.OPERATIONS_MULTISIG();

        uint256 vtPrice = IPufferOracle(address(validatorTicket.PUFFER_ORACLE())).getValidatorTicketPrice();
        uint256 requiredETH = vtAmount.mulDiv(vtPrice, 1 ether, Math.Rounding.Ceil);
        uint256 pufEthAmount = PufferVaultV3(payable(validatorTicket.PUFFER_VAULT())).convertToSharesUp(requiredETH);

        deal(address(validatorTicket.PUFFER_VAULT()), recipient, pufEthAmount);

        uint256 initialTreasuryBalance = IERC20(validatorTicket.PUFFER_VAULT()).balanceOf(treasury);
        uint256 initialOperationsMultisigBalance = IERC20(validatorTicket.PUFFER_VAULT()).balanceOf(operationsMultisig);
        uint256 initialBurnedAmount = IERC20(validatorTicket.PUFFER_VAULT()).totalSupply();

        vm.startPrank(recipient);
        IERC20(validatorTicket.PUFFER_VAULT()).approve(address(validatorTicket), pufEthAmount);
        uint256 pufEthUsed = validatorTicket.purchaseValidatorTicketWithPufETH(recipient, vtAmount);
        vm.stopPrank();

        uint256 expectedTreasuryAmount = pufEthAmount.mulDiv(INITIAL_PROTOCOL_FEE, 10000, Math.Rounding.Ceil);
        uint256 expectedGuardianAmount = pufEthAmount.mulDiv(INITIAL_GUARDIANS_FEE, 10000, Math.Rounding.Ceil);
        uint256 expectedBurnAmount = pufEthAmount - expectedTreasuryAmount - expectedGuardianAmount;

        assertEq(pufEthUsed, pufEthAmount, "PufETH used should match expected");
        assertEq(validatorTicket.balanceOf(recipient), vtAmount, "Should mint requested VTs");
        assertEq(
            IERC20(validatorTicket.PUFFER_VAULT()).balanceOf(treasury) - initialTreasuryBalance,
            expectedTreasuryAmount,
            "Treasury should receive 5% of pufETH"
        );
        assertEq(
            IERC20(validatorTicket.PUFFER_VAULT()).balanceOf(operationsMultisig) - initialOperationsMultisigBalance,
            expectedGuardianAmount,
            "Operations Multisig should receive 0.5% of pufETH"
        );
        assertEq(
            initialBurnedAmount - IERC20(validatorTicket.PUFFER_VAULT()).totalSupply(),
            expectedBurnAmount,
            "Remaining pufETH should be burned"
        );
    }

    function test_dao_fee_rate_changes() public {
        vm.startPrank(_getDAO());

        // Test protocol fee rate change
        vm.expectEmit(true, true, true, true);
        emit IValidatorTicket.ProtocolFeeChanged(INITIAL_PROTOCOL_FEE, 800);
        validatorTicket.setProtocolFeeRate(800); // 8%
        assertEq(validatorTicket.getProtocolFeeRate(), 800, "Protocol fee should be updated");

        // Test guardians fee rate change
        vm.expectEmit(true, true, true, true);
        emit IValidatorTicket.GuardiansFeeChanged(INITIAL_GUARDIANS_FEE, 100);
        validatorTicket.setGuardiansFeeRate(100); // 1%
        assertEq(validatorTicket.getGuardiansFeeRate(), 100, "Guardians fee should be updated");

        vm.stopPrank();
    }

    function test_purchase_validator_ticket_with_eth() public {
        uint256 amount = 10 ether;
        address recipient = alice;

        // Get initial balances
        (uint256 initialTreasuryBalance, uint256 initialGuardianBalance, uint256 initialVaultBalance) = _getBalances();

        // Purchase VTs
        vm.deal(recipient, amount);
        vm.prank(recipient);
        uint256 mintedAmount = validatorTicket.purchaseValidatorTicket{ value: amount }(recipient);

        // Verify minted amount
        uint256 expectedVTAmount = _calculateExpectedVTs(amount);
        assertEq(mintedAmount, expectedVTAmount, "Minted VT amount should match expected");
        assertEq(validatorTicket.balanceOf(recipient), expectedVTAmount, "VT balance should match expected");

        // Verify fee distributions
        _verifyFeeDistribution(amount, initialTreasuryBalance, initialGuardianBalance, initialVaultBalance);
    }

    function _getBalances() internal view returns (uint256, uint256, uint256) {
        return (
            validatorTicket.TREASURY().balance,
            validatorTicket.GUARDIAN_MODULE().balance,
            validatorTicket.PUFFER_VAULT().balance
        );
    }

    function _calculateExpectedVTs(uint256 amount) internal view returns (uint256) {
        uint256 vtPrice = IPufferOracle(address(validatorTicket.PUFFER_ORACLE())).getValidatorTicketPrice();
        return (amount * 1 ether) / vtPrice;
    }

    function _verifyFeeDistribution(
        uint256 amount,
        uint256 initialTreasuryBalance,
        uint256 initialGuardianBalance,
        uint256 initialVaultBalance
    ) internal {
        address treasury = validatorTicket.TREASURY();
        address guardianModule = validatorTicket.GUARDIAN_MODULE();
        address vault = validatorTicket.PUFFER_VAULT();

        uint256 treasuryAmount = amount.mulDiv(INITIAL_PROTOCOL_FEE, 10000, Math.Rounding.Ceil);
        uint256 guardianAmount = amount.mulDiv(INITIAL_GUARDIANS_FEE, 10000, Math.Rounding.Ceil);
        uint256 vaultAmount = amount - treasuryAmount - guardianAmount;

        assertEq(treasury.balance - initialTreasuryBalance, treasuryAmount, "Treasury should receive correct fee");
        assertEq(
            guardianModule.balance - initialGuardianBalance, guardianAmount, "Guardians should receive correct fee"
        );
        assertEq(vault.balance - initialVaultBalance, vaultAmount, "Vault should receive remaining amount");
    }

    function test_purchase_validator_ticket_with_eth_over_burst_threshold() public {
        uint256 amount = 10 ether;
        address recipient = alice;
        address treasury = validatorTicket.TREASURY();

        // Mock oracle
        vm.mockCall(
            address(validatorTicket.PUFFER_ORACLE()),
            abi.encodeWithSelector(IPufferOracle.isOverBurstThreshold.selector),
            abi.encode(true)
        );

        uint256 initialTreasuryBalance = treasury.balance;

        // Purchase VTs
        vm.deal(recipient, amount);
        vm.prank(recipient);
        uint256 mintedAmount = validatorTicket.purchaseValidatorTicket{ value: amount }(recipient);

        // Verify minted amount
        uint256 expectedVTAmount = _calculateExpectedVTs(amount);
        assertEq(mintedAmount, expectedVTAmount, "Minted VT amount should match expected");
        assertEq(validatorTicket.balanceOf(recipient), expectedVTAmount, "VT balance should match expected");

        // Verify all ETH went to treasury
        assertEq(
            treasury.balance - initialTreasuryBalance,
            amount,
            "Treasury should receive all ETH when over burst threshold"
        );
    }
}
