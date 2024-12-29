// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IAccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Merkle } from "murky/Merkle.sol";
import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { IPufferVaultV3 } from "src/interface/IPufferVaultV3.sol";
import { ROLE_ID_DAO, ROLE_ID_PUFFER_PROTOCOL, ROLE_ID_GRANT_MANAGER } from "script/Roles.sol";

contract PufferVaultV3ForkTest is MainnetForkTestHelper {
    address internal pufferCommunityMultisig = 0x446d4d6b26815f9bA78B5D454E303315D586Cb2a;
    address internal eigenlayerCommunityMultisig = 0xFEA47018D632A77bA579846c840d5706705Dc598;
    address internal lucidlyMultisig;
    address internal pointMarketMultisig;
    address internal grantManager;
    address[] internal grantees;
    bytes32 internal grantRoot;
    bytes32[][] internal grantProofs;
    uint256 internal currentEpochStartTime;

    function setUp() public virtual override {
        // Cancun upgrade
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19_431_593); //(Mar-14-2024 06:53:11 AM +UTC)

        // Setup actors
        vm.label(pufferCommunityMultisig, "pufferCommunityMultisig");
        vm.label(eigenlayerCommunityMultisig, "eigenlayerCommunityMultisig");

        lucidlyMultisig = makeAddr("lucidly");
        pointMarketMultisig = makeAddr("pointMarket");
        grantManager = makeAddr("grantManager");
        grantees = [pufferCommunityMultisig, eigenlayerCommunityMultisig, lucidlyMultisig, pointMarketMultisig];
        (grantRoot, grantProofs) = _buildMerkle(grantees);
        currentEpochStartTime = vm.getBlockTimestamp();

        // Setup contracts
        _setupLiveContracts();
        _upgradeToMainnetPuffer();
        _upgradeToMainnetV3Puffer(currentEpochStartTime);

        // Configure contracts
        vm.prank(address(timelock));
        accessManager.grantRole(ROLE_ID_GRANT_MANAGER, grantManager, 0);

        vm.prank(grantManager);
        pufferVault.setGrantRoot(grantRoot);
    }

    function test_SetGrantRoot_EmitGrantRootSet() public {
        grantees = [eigenlayerCommunityMultisig, pufferCommunityMultisig];
        (grantRoot,) = _buildMerkle(grantees);

        vm.prank(grantManager);
        vm.expectEmit();
        emit IPufferVaultV3.GrantRootSet(grantRoot);
        pufferVault.setGrantRoot(grantRoot);
    }

    function test_GetGrantInfo() public view {
        (
            bytes32 currentRoot,
            uint256 currentMaxGrantAmount,
            uint256 currentcurrentEpochStartTime,
            uint256 currentGrantEpochDuration
        ) = pufferVault.getGrantInfo();
        assertEq(currentRoot, grantRoot);
        assertEq(currentMaxGrantAmount, maxGrantAmount);
        assertEq(currentcurrentEpochStartTime, currentEpochStartTime);
        assertEq(currentGrantEpochDuration, grantEpochDuration);
    }

    function test_GetClaimableGrantEpoch() public {
        (uint256 initialGrantEpoch,) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(initialGrantEpoch, pufferVault.calculateGrantEpoch());

        // Set time to the end of the current grant epoch
        (,, uint256 epochStartTime, uint256 epochDuration) = pufferVault.getGrantInfo();
        vm.warp(epochStartTime + epochDuration - 1);

        (uint256 currentGrantEpoch,) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(currentGrantEpoch, initialGrantEpoch);

        // Set time to the beginning of the next grant epoch
        vm.warp(epochStartTime + epochDuration);

        (uint256 nextGrantEpoch,) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(nextGrantEpoch, currentGrantEpoch + 1);
    }

    function test_SetGrantRoot_RevertIf_UnuathorizedAccess() public {
        vm.prank(pufferCommunityMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, pufferCommunityMultisig)
        );
        pufferVault.setGrantRoot(grantRoot);
    }

    function test_ClaimGrant_EmitGrantPaidForNativePayment() public {
        uint256 grantAmount = maxGrantAmount;
        deal(address(pufferVault), grantAmount);

        // Set time to the end of the current grant epoch
        (,, uint256 epochStartTime, uint256 epochDuration) = pufferVault.getGrantInfo();
        vm.warp(epochStartTime + epochDuration - 1);

        uint256 grantEpoch = pufferVault.calculateGrantEpoch();
        bool isNative = true;

        vm.prank(pufferCommunityMultisig);
        vm.expectEmit();
        emit IPufferVaultV3.GrantPaid(grantees[0], grantEpoch, grantAmount, isNative);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);
    }

    function test_ClaimGrant_EmitGrantPaidForERC20Payment() public {
        uint256 grantAmount = maxGrantAmount;
        deal(address(_WETH), address(pufferVault), grantAmount);

        // Set time to the end of the current grant epoch
        (,, uint256 epochStartTime, uint256 epochDuration) = pufferVault.getGrantInfo();
        vm.warp(epochStartTime + epochDuration - 1);

        uint256 grantEpoch = pufferVault.calculateGrantEpoch();
        bool isNative = false;

        vm.prank(pufferCommunityMultisig);
        vm.expectEmit();
        emit IPufferVaultV3.GrantPaid(grantees[0], grantEpoch, grantAmount, isNative);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);
    }

    function test_ClaimGrant_ChangeBalancesForNativePayment() public {
        uint256 grantAmount = maxGrantAmount;
        deal(address(pufferVault), grantAmount);

        uint256 initialVaultBalance = address(pufferVault).balance;
        uint256 initialGranteeBalance = grantees[0].balance;
        bool isNative = true;

        vm.prank(pufferCommunityMultisig);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);

        uint256 currentVaultBalance = address(pufferVault).balance;
        assertEq(grantAmount, initialVaultBalance - currentVaultBalance);

        uint256 currentGranteeBalance = grantees[0].balance;
        assertEq(grantAmount, initialGranteeBalance + currentGranteeBalance);
    }

    function test_ClaimGrant_ChangeBalancesForERC20Payment() public {
        uint256 grantAmount = maxGrantAmount;
        deal(address(_WETH), address(pufferVault), grantAmount);

        uint256 initialVaultBalance = _WETH.balanceOf(address(pufferVault));
        uint256 initialGranteeBalance = _WETH.balanceOf(grantees[0]);
        bool isNative = false;

        vm.prank(pufferCommunityMultisig);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);

        uint256 currentVaultBalance = _WETH.balanceOf(address(pufferVault));
        assertEq(grantAmount, initialVaultBalance - currentVaultBalance);

        uint256 currentGranteeBalance = _WETH.balanceOf(grantees[0]);
        assertEq(grantAmount, initialGranteeBalance + currentGranteeBalance);
    }

    function test_ClaimGrant_MultipleTimesWithinSingleGrantEpoch() public {
        uint256 grantAmount = maxGrantAmount;
        deal(address(pufferVault), grantAmount * 2);

        (, uint256 claimableAmount) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(claimableAmount, grantAmount);

        bool isNative = true;
        vm.prank(pufferCommunityMultisig);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);

        (, claimableAmount) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(claimableAmount, 0);

        // Set time to the beginning of the next grant epoch
        (,, uint256 epochStartTime, uint256 epochDuration) = pufferVault.getGrantInfo();
        vm.warp(epochStartTime + epochDuration);

        (, claimableAmount) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(claimableAmount, grantAmount);

        vm.prank(pufferCommunityMultisig);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);

        (, claimableAmount) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(claimableAmount, 0);
    }

    function test_ClaimGrant_SingleTimeWithinMultipleGrantEpochs() public {
        uint256 grantAmount = maxGrantAmount / 2;
        deal(address(pufferVault), grantAmount * 2);

        (, uint256 claimableAmount) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(claimableAmount, maxGrantAmount);

        bool isNative = true;
        vm.prank(pufferCommunityMultisig);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);

        // Set time to the end of the current grant epoch
        (,, uint256 epochStartTime, uint256 epochDuration) = pufferVault.getGrantInfo();
        vm.warp(epochStartTime + epochDuration - 1);

        (, claimableAmount) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(claimableAmount, grantAmount);

        vm.prank(pufferCommunityMultisig);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);

        (, claimableAmount) = pufferVault.getClaimableGrant(pufferCommunityMultisig);
        assertEq(claimableAmount, 0);
    }

    function test_ClaimGrant_RevertIf_ZeroGrantAmount() public {
        uint256 grantAmount = 0;
        bool isNative = true;

        vm.prank(pufferCommunityMultisig);
        vm.expectRevert(abi.encodeWithSelector(IPufferVaultV3.InvalidGrantAmount.selector, grantAmount));
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);
    }

    function test_ClaimGrant_RevertIf_AboveMaxGrantAmount() public {
        uint256 grantAmount = maxGrantAmount + 1;
        bool isNative = true;

        vm.prank(pufferCommunityMultisig);
        vm.expectRevert(abi.encodeWithSelector(IPufferVaultV3.InvalidGrantAmount.selector, grantAmount));
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);
    }

    function test_ClaimGrant_RevertIf_IneligibleGrantee() public {
        uint256 grantAmount = maxGrantAmount;
        bool isNative = true;

        vm.prank(pufferCommunityMultisig);
        vm.expectRevert(abi.encodeWithSelector(IPufferVaultV3.IneligibleGrantee.selector, grantees[0]));
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[1]);
    }

    function test_ClaimGrant_RevertIf_UnavailableGrantAmount() public {
        uint256 grantAmount = maxGrantAmount;
        deal(address(pufferVault), grantAmount);

        bool isNative = true;

        vm.startPrank(pufferCommunityMultisig);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);

        uint256 newGrantAmount = 1;
        vm.expectRevert(abi.encodeWithSelector(IPufferVaultV3.UnavailableGrantAmount.selector, newGrantAmount, 0));
        pufferVault.claimGrant(newGrantAmount, isNative, grantProofs[0]);

        vm.stopPrank();
    }

    function test_ClaimGrant_RevertIf_InsufficientVaultBalance() public {
        uint256 grantAmount = maxGrantAmount;
        bool isNative = true;

        vm.prank(pufferCommunityMultisig);
        vm.expectRevert(abi.encodeWithSelector(Address.AddressInsufficientBalance.selector, address(pufferVault)));
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);
    }

    function test_ClaimGrant_RevertIf_FailedInnerVaultCall() public {
        uint256 grantAmount = maxGrantAmount;
        bool isNative = false;

        vm.prank(pufferCommunityMultisig);
        vm.expectRevert(Address.FailedInnerCall.selector);
        pufferVault.claimGrant(grantAmount, isNative, grantProofs[0]);
    }

    function _buildMerkle(address[] memory _grantees) private returns (bytes32, bytes32[][] memory) {
        uint256 granteeCount = _grantees.length;
        bytes32[] memory data = new bytes32[](granteeCount);
        bytes32[][] memory proofs = new bytes32[][](granteeCount);

        for (uint256 i = 0; i < granteeCount; ++i) {
            data[i] = keccak256(abi.encodePacked(_grantees[i]));
        }

        Merkle merkle = new Merkle();
        bytes32 root = merkle.getRoot(data);

        for (uint256 i = 0; i < granteeCount; ++i) {
            proofs[i] = merkle.getProof(data, i);
        }

        return (root, proofs);
    }
}
