// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IAccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Merkle } from "murky/Merkle.sol";
import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { IPufferVaultV3 } from "../../src/interface/IPufferVaultV3.sol";
import { ROLE_ID_DAO, ROLE_ID_PUFFER_PROTOCOL, ROLE_ID_GRANT_MANAGER } from "../../script/Roles.sol";

contract PufferVaultV3ForkTest is MainnetForkTestHelper {
    address internal grantManager;
    address internal eigenlayerCommunityMultisig = 0xFEA47018D632A77bA579846c840d5706705Dc598;
    address internal pufferCommunityMultisig = 0x446d4d6b26815f9bA78B5D454E303315D586Cb2a;
    address internal lucidlyMultisig;
    address internal pointMarketMultisig;
    address[] internal grantees;

    function setUp() public virtual override {
        // Cancun upgrade
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19431593); //(Mar-14-2024 06:53:11 AM +UTC)

        // Setup actors
        grantManager = makeAddr("grantManager");
        eigenlayerCommunityMultisig;
        pufferCommunityMultisig;
        lucidlyMultisig = makeAddr("lucidly");
        pointMarketMultisig = makeAddr("pointMarket");
        grantees = [eigenlayerCommunityMultisig, pufferCommunityMultisig, lucidlyMultisig, pointMarketMultisig];

        deal(grantManager, 100 ether);

        // Setup contracts
        _setupLiveContracts();
        _upgradeToMainnetPuffer();
        _upgradeToMainnetV3Puffer();

        // Configure contracts
        vm.prank(address(timelock));
        accessManager.grantRole(ROLE_ID_GRANT_MANAGER, grantManager, 0);
    }

    function test_SetGrantRoot_EmitGrantRootSet() external {
        (bytes32 root,) = _buildMerkle(grantees);

        vm.prank(grantManager);
        vm.expectEmit();
        emit IPufferVaultV3.GrantRootSet(root);
        pufferVault.setGrantRoot(root);
    }

    function test_SetGrantRoot_GetGrantInfo() external {
        (bytes32 root,) = _buildMerkle(grantees);

        vm.prank(grantManager);
        pufferVault.setGrantRoot(root);

        (
            bytes32 currentRoot,
            uint256 currentMaxGrantAmount,
            uint256 currentGrantEpochStartTime,
            uint256 currentGrantEpochDuration
        ) = pufferVault.getGrantInfo();
        assertEq(currentRoot, root);
        assertEq(currentMaxGrantAmount, maxGrantAmount);
        assertEq(currentGrantEpochStartTime, grantEpochStartTime);
        assertEq(currentGrantEpochDuration, grantEpochDuration);
    }

    function test_RevertIf_UnuathorizedAccess() external {
        (bytes32 root,) = _buildMerkle(grantees);

        vm.prank(pufferCommunityMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, pufferCommunityMultisig)
        );
        pufferVault.setGrantRoot(root);
    }

    function _buildMerkle(address[] memory _grantees) public returns (bytes32, bytes32[][] memory) {
        Merkle merkle = new Merkle();

        uint256 granteeCount = _grantees.length;
        bytes32[] memory data = new bytes32[](granteeCount);
        bytes32[][] memory proofs = new bytes32[][](granteeCount);

        for (uint256 i = 0; i < granteeCount; ++i) {
            data[i] = keccak256(abi.encode(_grantees[i]));
        }

        bytes32 root = merkle.getRoot(data);
        for (uint256 i = 0; i < granteeCount; ++i) {
            proofs[i] = merkle.getProof(data, i);
        }

        return (root, proofs);
    }
}
