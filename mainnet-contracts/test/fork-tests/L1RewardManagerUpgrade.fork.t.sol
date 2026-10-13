// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { L1RewardManager } from "../../src/L1RewardManager.sol";
import { IL1RewardManager } from "../../src/interface/IL1RewardManager.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { UpgradeL1RewardManager } from "../../script/UpgradeL1RewardManager.s.sol";
import {
    ROLE_ID_BRIDGE,
    ROLE_ID_L1_REWARD_MANAGER,
    ROLE_ID_REWARD_WATCHER,
    ROLE_ID_REWARDS_MINTER
} from "../../script/Roles.sol";

/**
 * @notice Runs the upgrade script on a Mainnet fork, executes both Timelock transactions,
 * then goes through mint -> freeze -> revert -> mint again -> claim
 */
contract L1RewardManagerUpgradeForkTest is Test {
    address internal constant TIMELOCK = 0x3C28B7c7Ba1A1f55c9Ce66b263B33B204f2126eA;
    address internal constant OPS_MULTISIG = 0xC0896ab1A8cae8c2C1d27d011eb955Cca955580d;
    address internal constant ACCESS_MANAGER = 0x8c1686069474410E6243425f4a10177a94EBEE11;
    address internal constant L1_REWARD_MANAGER = 0x157788cc028Ac6405bD406f2D1e0A8A22b3cf17b;
    address internal constant PUFFER_VAULT = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    address internal constant PUFETH_OFT_ADAPTER = 0xa4931a9F9Aaf79057334371D6f62164743f97b18;
    address internal constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant CONNEXT = 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6;

    L1RewardManager internal rewardManager = L1RewardManager(L1_REWARD_MANAGER);
    PufferVaultV5 internal vault = PufferVaultV5(payable(PUFFER_VAULT));
    AccessManager internal accessManager = AccessManager(ACCESS_MANAGER);

    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 26183219); // Oct-13-2026
    }

    function test_upgrade_and_reward_flow() public {
        uint256 lastIntervalEndEpoch = rewardManager.getLastIntervalEndEpoch();
        uint256 currentIntervalEndEpoch = rewardManager.getCurrentIntervalEndEpoch();
        uint256 pufETHBalanceBefore = IERC20(PUFFER_VAULT).balanceOf(L1_REWARD_MANAGER);

        // The same entry point as the deployment, the reward watcher defaults to the Operations Multisig
        UpgradeL1RewardManager script = new UpgradeL1RewardManager();
        script.run();

        // Execute both Timelock transactions in the printed order
        vm.startPrank(TIMELOCK);
        (bool success,) = ACCESS_MANAGER.call(script.accessManagerCallData());
        assertTrue(success, "AccessManager multicall");
        (success,) = L1_REWARD_MANAGER.call(script.upgradeCallData());
        assertTrue(success, "upgradeToAndCall");
        vm.stopPrank();

        // The state is kept and `initializeV2` ran
        assertEq(rewardManager.getLastIntervalEndEpoch(), lastIntervalEndEpoch, "last interval end epoch");
        assertEq(rewardManager.getCurrentIntervalEndEpoch(), currentIntervalEndEpoch, "current interval end epoch");
        assertEq(rewardManager.getClaimingDelay(), 24 hours, "claiming delay");
        assertEq(IERC20(PUFFER_VAULT).allowance(L1_REWARD_MANAGER, PUFETH_OFT_ADAPTER), 0, "OFT allowance");
        assertEq(IERC20(PUFFER_VAULT).balanceOf(L1_REWARD_MANAGER), pufETHBalanceBefore, "pufETH balance");
        assertEq(rewardManager.getNewestIntervalId(), bytes32(0), "newest interval");

        // Roles
        _assertRole(ROLE_ID_BRIDGE, LZ_ENDPOINT, false);
        _assertRole(ROLE_ID_BRIDGE, CONNEXT, false);
        _assertRole(ROLE_ID_BRIDGE, OPS_MULTISIG, false);
        _assertRole(ROLE_ID_REWARD_WATCHER, OPS_MULTISIG, true);
        _assertRole(ROLE_ID_L1_REWARD_MANAGER, OPS_MULTISIG, false);
        _assertRole(ROLE_ID_L1_REWARD_MANAGER, L1_REWARD_MANAGER, true);

        // The bridging entry point is closed
        vm.prank(LZ_ENDPOINT);
        (success,) = L1_REWARD_MANAGER.call(
            abi.encodeWithSignature(
                "lzCompose(address,bytes32,bytes,address,bytes)", PUFETH_OFT_ADAPTER, bytes32(0), "", address(0), ""
            )
        );
        assertFalse(success, "lzCompose");

        // The Operations Multisig can not mint or burn the vault rewards directly anymore
        vm.startPrank(OPS_MULTISIG);
        vm.expectRevert();
        vault.mintRewards(1 ether);
        vm.expectRevert();
        vault.revertMintRewards(0, 1 ether);
        vm.stopPrank();

        // Role 28 is granted through the Timelock for each mint
        vm.prank(TIMELOCK);
        accessManager.grantRole(ROLE_ID_REWARDS_MINTER, minter, 0);

        uint256 rewardsAmount = 10 ether;
        IL1RewardManager.MintRewardsParams memory params = IL1RewardManager.MintRewardsParams({
            rewardsAmount: rewardsAmount,
            startEpoch: currentIntervalEndEpoch + 1,
            endEpoch: currentIntervalEndEpoch + 225,
            // Single leaf tree, the root is the leaf
            rewardsRoot: keccak256(bytes.concat(keccak256(abi.encode(alice, false, rewardsAmount)))),
            rewardsURI: "ipfs://rewards"
        });
        bytes32 intervalId = rewardManager.getIntervalId(params.startEpoch, params.endEpoch);
        uint256 totalRewardMintAmountBefore = vault.getTotalRewardMintAmount();

        vm.prank(minter);
        rewardManager.mintRewards(params);
        assertEq(vault.getTotalRewardMintAmount(), totalRewardMintAmountBefore + rewardsAmount, "minted");

        // The Operations Multisig freezes as the watcher, then reverts as the DAO
        vm.startPrank(OPS_MULTISIG);
        rewardManager.freezeInterval(params.startEpoch, params.endEpoch);
        rewardManager.revertInterval(params.startEpoch, params.endEpoch);
        vm.stopPrank();
        assertEq(vault.getTotalRewardMintAmount(), totalRewardMintAmountBefore, "reverted mint amount");
        assertEq(IERC20(PUFFER_VAULT).balanceOf(L1_REWARD_MANAGER), pufETHBalanceBefore, "reverted pufETH");
        assertEq(rewardManager.getCurrentIntervalEndEpoch(), currentIntervalEndEpoch, "epoch pointer");

        // Mint the same epochs again after the mint frequency, claim after the claiming delay
        vm.warp(block.timestamp + 72 hours);
        vm.prank(minter);
        rewardManager.mintRewards(params);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = IL1RewardManager.ClaimOrder({
            intervalId: intervalId,
            amount: rewardsAmount,
            isL1Contract: false,
            account: alice,
            merkleProof: new bytes32[](0)
        });

        vm.expectPartialRevert(IL1RewardManager.ClaimingLocked.selector);
        rewardManager.claimRewards(claimOrders);

        vm.warp(block.timestamp + 24 hours);
        rewardManager.claimRewards(claimOrders);
        assertGt(IERC20(PUFFER_VAULT).balanceOf(alice), 0, "claimed");
        assertTrue(rewardManager.isClaimed(intervalId, alice), "isClaimed");
    }

    function _assertRole(uint64 roleId, address account, bool expected) internal view {
        (bool isMember,) = accessManager.hasRole(roleId, account);
        assertEq(isMember, expected, "role");
    }
}
