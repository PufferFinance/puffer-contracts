// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IL1RewardManager } from "../../src/interface/IL1RewardManager.sol";
import { L1RewardManager } from "../../src/L1RewardManager.sol";
import { L1RewardManagerStorage } from "../../src/L1RewardManagerStorage.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Merkle } from "murky/Merkle.sol";
import {
    ROLE_ID_L1_REWARD_MANAGER,
    ROLE_ID_REWARDS_MINTER,
    ROLE_ID_REWARD_WATCHER,
    ADMIN_ROLE
} from "../../script/Roles.sol";
import { GenerateRewardManagerCalldata } from
    "../../script/AccessManagerMigrations/03_GenerateRewardManagerCalldata.s.sol";

contract L1RewardManagerTest is UnitTestHelper {
    struct MerkleProofData {
        address account;
        uint256 amount;
        bool isL1Contract;
    }

    // keccak256(abi.encode(uint256(keccak256("l1rewardmanager.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant REWARD_MANAGER_STORAGE_LOCATION =
        0xb18045c429f6c4e33b477568e1a40f795629ac8937518d2b48a302e4c0fbb700;

    uint256 internal constant CLAIMING_DELAY = 24 hours;
    uint256 internal constant MINT_FREQUENCY = 72 hours;

    address rewardWatcher = makeAddr("rewardWatcher");
    address rewardsMinter = makeAddr("rewardsMinter");

    Merkle merkle;
    bytes32[] leaves;

    function setUp() public override {
        super.setUp();

        merkle = new Merkle();

        L1RewardManager l1RewardManagerImpl = new L1RewardManager(address(pufferVault));
        l1RewardManager = L1RewardManager(
            address(
                new ERC1967Proxy(
                    address(l1RewardManagerImpl), abi.encodeCall(L1RewardManager.initialize, (address(accessManager)))
                )
            )
        );
        vm.label(address(l1RewardManager), "L1RewardManager");

        vm.startPrank(_broadcaster);

        // Same order as on mainnet: the proxy is at version 1, then the upgrade runs initializeV2
        l1RewardManager.initializeV2(CLAIMING_DELAY, uint104(MINT_FREQUENCY), address(0));

        bytes4[] memory vaultSelectors = new bytes4[](2);
        vaultSelectors[0] = PufferVaultV5.mintRewards.selector;
        vaultSelectors[1] = PufferVaultV5.revertMintRewards.selector;
        accessManager.setTargetFunctionRole(address(pufferVault), vaultSelectors, ROLE_ID_L1_REWARD_MANAGER);
        accessManager.grantRole(ROLE_ID_L1_REWARD_MANAGER, address(l1RewardManager), 0);

        bytes memory cd = new GenerateRewardManagerCalldata().generateL1Calldata(
            address(l1RewardManager), rewardWatcher, new address[](0), new address[](0)
        );
        (bool success,) = address(accessManager).call(cd);
        require(success, "failed setupAccess GenerateRewardManagerCalldata");

        accessManager.grantRole(ROLE_ID_REWARDS_MINTER, rewardsMinter, 0);

        vm.stopPrank();

        vm.prank(DAO);
        l1RewardManager.setAllowedRewardMintAmount(100 ether);

        vm.warp(365 days);
    }

    function test_constructor() public {
        L1RewardManager impl = new L1RewardManager(address(pufferVault));
        assertEq(address(impl.PUFFER_VAULT()), address(pufferVault), "vault");
    }

    function testRevert_constructorZeroAddress() public {
        vm.expectRevert(IL1RewardManager.InvalidAddress.selector);
        new L1RewardManager(address(0));
    }

    function test_initialize() public {
        L1RewardManager proxy = _deployVersion1Proxy();

        assertEq(proxy.authority(), address(accessManager), "access manager");
        // The settings come from initializeV2
        assertEq(proxy.getClaimingDelay(), 0, "claiming delay");
        assertEq(_getAllowedRewardMintFrequency(proxy), 0, "mint frequency");
    }

    function testRevert_initializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        l1RewardManager.initialize(address(accessManager));
    }

    function test_initializeV2() public {
        L1RewardManager proxy = _deployVersion1Proxy();
        address oftAdapter = makeAddr("oftAdapter");

        // The bridging version left a small allowance to the OFT adapter
        vm.prank(address(proxy));
        pufferVault.approve(oftAdapter, 481127112341);

        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.ClaimingDelayUpdated(0, 12 hours);
        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.AllowedRewardMintFrequencyUpdated(0, 96 hours);
        vm.prank(_broadcaster);
        proxy.initializeV2(12 hours, 96 hours, oftAdapter);

        assertEq(proxy.getClaimingDelay(), 12 hours, "claiming delay");
        assertEq(_getAllowedRewardMintFrequency(proxy), 96 hours, "mint frequency");
        assertEq(pufferVault.allowance(address(proxy), oftAdapter), 0, "allowance");

        vm.prank(_broadcaster);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        proxy.initializeV2(12 hours, 96 hours, oftAdapter);
    }

    function test_upgradeOnlyByAdmin() public {
        L1RewardManager newImplementation = new L1RewardManager(address(pufferVault));

        vm.prank(DAO);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, DAO));
        l1RewardManager.upgradeToAndCall(address(newImplementation), "");

        vm.prank(_broadcaster);
        l1RewardManager.upgradeToAndCall(address(newImplementation), "");
    }

    function testRevert_initializeV2Unauthorized() public {
        L1RewardManager proxy = _deployVersion1Proxy();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        proxy.initializeV2(12 hours, 96 hours, address(0));
    }

    function testRevert_initializeV2InvalidValues() public {
        L1RewardManager proxy = _deployVersion1Proxy();

        vm.startPrank(_broadcaster);
        vm.expectRevert(IL1RewardManager.InvalidClaimingDelay.selector);
        proxy.initializeV2(1 hours, 96 hours, address(0));

        vm.expectRevert(IL1RewardManager.InvalidMintFrequency.selector);
        proxy.initializeV2(12 hours, 20 hours, address(0));
        vm.stopPrank();
    }

    function test_mintRewards() public {
        MerkleProofData[] memory data = _aliceAndBob(6 ether, 4 ether);
        bytes32 root = _buildMerkleTree(data);
        bytes32 intervalId = l1RewardManager.getIntervalId(1, 100);

        uint256 totalRewardMintAmountBefore = pufferVault.getTotalRewardMintAmount();
        uint256 rate = pufferVault.convertToShares(1 ether);
        uint256 expectedPufETH = rate * 10 ether / 1 ether;

        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.RewardsMinted({
            intervalId: intervalId,
            rewardsRoot: root,
            rewardsAmount: 10 ether,
            pufETHAmount: expectedPufETH,
            ethToPufETHRate: rate,
            startEpoch: 1,
            endEpoch: 100,
            claimableAt: block.timestamp + CLAIMING_DELAY,
            rewardsURI: "uri"
        });
        _mintRewards(10 ether, 1, 100, root);

        L1RewardManagerStorage.Interval memory interval = l1RewardManager.getInterval(intervalId);
        assertEq(interval.startEpoch, 1, "start epoch");
        assertEq(interval.endEpoch, 100, "end epoch");
        assertEq(interval.claimableAt, block.timestamp + CLAIMING_DELAY, "claimableAt");
        assertEq(interval.pufETHAmount, expectedPufETH, "pufETH amount");
        assertEq(interval.ethAmount, 10 ether, "eth amount");
        assertEq(interval.claimedPufETHAmount, 0, "claimed");
        assertEq(uint256(interval.status), uint256(L1RewardManagerStorage.IntervalStatus.ACTIVE), "status");
        assertEq(interval.ethToPufETHRate, rate, "rate");
        assertEq(interval.rewardsRoot, root, "root");

        assertEq(l1RewardManager.getNewestIntervalId(), intervalId, "newest interval");
        assertEq(l1RewardManager.getLastIntervalEndEpoch(), 0, "last end epoch");
        assertEq(l1RewardManager.getCurrentIntervalEndEpoch(), 100, "current end epoch");
        assertEq(pufferVault.balanceOf(address(l1RewardManager)), expectedPufETH, "minted into the contract");
        assertEq(
            pufferVault.getTotalRewardMintAmount(), totalRewardMintAmountBefore + 10 ether, "vault reward mint amount"
        );
        assertTrue(l1RewardManager.isClaimingLocked(intervalId), "locked during the delay");
    }

    function testRevert_mintRewardsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        l1RewardManager.mintRewards(_mintParams(1 ether, 1, 100, keccak256("root")));
    }

    function testRevert_mintRewardsInvalidRoot() public {
        vm.prank(rewardsMinter);
        vm.expectRevert(IL1RewardManager.InvalidRewardsRoot.selector);
        l1RewardManager.mintRewards(_mintParams(1 ether, 1, 100, bytes32(0)));
    }

    function testRevert_mintRewardsZeroAmount() public {
        vm.prank(rewardsMinter);
        vm.expectRevert(IL1RewardManager.InvalidMintAmount.selector);
        l1RewardManager.mintRewards(_mintParams(0, 1, 100, keccak256("root")));
    }

    function testRevert_mintRewardsAboveAllowedAmount() public {
        vm.prank(rewardsMinter);
        vm.expectRevert(IL1RewardManager.InvalidMintAmount.selector);
        l1RewardManager.mintRewards(_mintParams(100 ether + 1, 1, 100, keccak256("root")));
    }

    function testRevert_mintRewardsEndEpochBeforeStartEpoch() public {
        vm.prank(rewardsMinter);
        vm.expectRevert(IL1RewardManager.InvalidEndEpoch.selector);
        l1RewardManager.mintRewards(_mintParams(1 ether, 100, 99, keccak256("root")));
    }

    function test_mintRewardsSingleEpoch() public {
        _mintRewards(1 ether, 5, 5, keccak256("root"));
        assertEq(l1RewardManager.getCurrentIntervalEndEpoch(), 5, "current end epoch");
    }

    function testRevert_mintRewardsTooOften() public {
        _mintRewards(1 ether, 1, 100, keccak256("root"));

        // The claiming delay has passed, but the mint frequency has not
        vm.warp(block.timestamp + MINT_FREQUENCY - 1);

        vm.prank(rewardsMinter);
        vm.expectRevert(IL1RewardManager.NotAllowedMintFrequency.selector);
        l1RewardManager.mintRewards(_mintParams(1 ether, 101, 200, keccak256("root2")));
    }

    function testRevert_mintRewardsInvalidStartEpoch() public {
        _mintRewards(1 ether, 1, 100, keccak256("root"));
        vm.warp(block.timestamp + MINT_FREQUENCY);

        vm.startPrank(rewardsMinter);
        vm.expectRevert(IL1RewardManager.InvalidStartEpoch.selector);
        l1RewardManager.mintRewards(_mintParams(1 ether, 100, 200, keccak256("root2")));

        vm.expectRevert(IL1RewardManager.InvalidStartEpoch.selector);
        l1RewardManager.mintRewards(_mintParams(1 ether, 50, 200, keccak256("root2")));
        vm.stopPrank();
    }

    function testRevert_mintRewardsWhileNewestIntervalIsLocked() public {
        // With the limits in the contract (mint frequency >= 72 hours >= claiming delay) the newest interval is
        // always out of its claiming delay when the next mint is allowed. This check protects against a wrong
        // frequency in storage.
        _setAllowedRewardMintFrequencyInStorage(1 hours);

        bytes32 intervalId = _mintRewards(1 ether, 1, 100, keccak256("root"));

        // The mint frequency has passed, but the newest interval is still in its claiming delay
        vm.warp(block.timestamp + 1 hours);
        assertTrue(l1RewardManager.isClaimingLocked(intervalId), "still locked");

        vm.prank(rewardsMinter);
        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.PreviousIntervalLocked.selector, intervalId));
        l1RewardManager.mintRewards(_mintParams(1 ether, 101, 200, keccak256("root2")));

        // After the claiming delay the next interval can be minted
        vm.warp(l1RewardManager.getInterval(intervalId).claimableAt);
        _mintRewards(1 ether, 101, 200, keccak256("root2"));
    }

    function testRevert_mintRewardsWhileNewestIntervalIsFrozen() public {
        bytes32 intervalId = _mintRewards(1 ether, 1, 100, keccak256("root"));

        vm.prank(rewardWatcher);
        l1RewardManager.freezeInterval(1, 100);

        vm.warp(block.timestamp + MINT_FREQUENCY);

        vm.prank(rewardsMinter);
        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.PreviousIntervalLocked.selector, intervalId));
        l1RewardManager.mintRewards(_mintParams(1 ether, 101, 200, keccak256("root2")));
    }

    function testRevert_mintRewardsWithoutClaimingDelay() public {
        // Simulates an upgrade that was done without `initializeV2`
        vm.store(address(l1RewardManager), bytes32(uint256(REWARD_MANAGER_STORAGE_LOCATION) + 5), bytes32(0));
        assertEq(l1RewardManager.getClaimingDelay(), 0, "claiming delay slot");

        vm.prank(rewardsMinter);
        vm.expectRevert(IL1RewardManager.InvalidClaimingDelay.selector);
        l1RewardManager.mintRewards(_mintParams(1 ether, 1, 100, keccak256("root")));
    }

    function test_consecutiveMints() public {
        bytes32 first = _mintRewards(1 ether, 1, 100, keccak256("root1"));
        vm.warp(block.timestamp + MINT_FREQUENCY);
        bytes32 second = _mintRewards(2 ether, 101, 200, keccak256("root2"));
        vm.warp(block.timestamp + MINT_FREQUENCY);
        // A gap between the intervals is allowed
        bytes32 third = _mintRewards(3 ether, 250, 300, keccak256("root3"));

        assertEq(l1RewardManager.getNewestIntervalId(), third, "newest interval");
        assertEq(l1RewardManager.getLastIntervalEndEpoch(), 200, "last end epoch");
        assertEq(l1RewardManager.getCurrentIntervalEndEpoch(), 300, "current end epoch");
        assertEq(l1RewardManager.getInterval(first).ethAmount, 1 ether, "first");
        assertEq(l1RewardManager.getInterval(second).ethAmount, 2 ether, "second");
        assertEq(l1RewardManager.getInterval(third).ethAmount, 3 ether, "third");
    }

    function test_claimRewards() public {
        MerkleProofData[] memory data = _aliceAndBob(6 ether, 4 ether);
        bytes32 root = _buildMerkleTree(data);
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, root);
        uint256 rate = l1RewardManager.getInterval(intervalId).ethToPufETHRate;

        vm.warp(block.timestamp + CLAIMING_DELAY);
        assertFalse(l1RewardManager.isClaimingLocked(intervalId), "unlocked");

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](2);
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);
        claimOrders[1] = _claimOrder(intervalId, data[1], 1);

        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.RewardsClaimed(alice, intervalId, 6 ether, 6 ether * rate / 1 ether);
        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.RewardsClaimed(bob, intervalId, 4 ether, 4 ether * rate / 1 ether);
        l1RewardManager.claimRewards(claimOrders);

        assertEq(pufferVault.balanceOf(alice), 6 ether * rate / 1 ether, "alice pufETH");
        assertEq(pufferVault.balanceOf(bob), 4 ether * rate / 1 ether, "bob pufETH");
        assertTrue(l1RewardManager.isClaimed(intervalId, alice), "alice claimed");
        assertTrue(l1RewardManager.isClaimed(intervalId, bob), "bob claimed");
        assertEq(
            l1RewardManager.getInterval(intervalId).claimedPufETHAmount,
            pufferVault.balanceOf(alice) + pufferVault.balanceOf(bob),
            "claimed pufETH amount"
        );
    }

    function test_claimRewardsForAnotherAccount() public {
        MerkleProofData[] memory data = _aliceAndBob(6 ether, 4 ether);
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, _buildMerkleTree(data));
        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);

        // Anyone can submit the claim, the pufETH goes to the account in the leaf
        vm.prank(charlie);
        l1RewardManager.claimRewards(claimOrders);

        assertGt(pufferVault.balanceOf(alice), 0, "alice got the rewards");
        assertEq(pufferVault.balanceOf(charlie), 0, "caller got nothing");
    }

    function test_claimRewardsForL1ContractLeaf() public {
        // On L2 an L1 contract had to set a claimer. On L1 the contract receives the rewards itself
        MerkleProofData[] memory data = new MerkleProofData[](2);
        data[0] = MerkleProofData({ account: address(pufferModuleManager), amount: 3 ether, isL1Contract: true });
        data[1] = MerkleProofData({ account: bob, amount: 1 ether, isL1Contract: false });
        bytes32 intervalId = _mintRewards(4 ether, 1, 100, _buildMerkleTree(data));
        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);
        l1RewardManager.claimRewards(claimOrders);

        assertGt(pufferVault.balanceOf(address(pufferModuleManager)), 0, "contract got the rewards");
    }

    function test_claimRewardsFromDifferentIntervals() public {
        MerkleProofData[] memory data1 = _aliceAndBob(6 ether, 4 ether);
        bytes32 first = _mintRewards(10 ether, 1, 100, _buildMerkleTree(data1));
        IL1RewardManager.ClaimOrder memory aliceFirst = _claimOrder(first, data1[0], 0);

        // The rate changes between the two intervals
        vm.deal(address(pufferVault), address(pufferVault).balance + 100 ether);

        vm.warp(block.timestamp + MINT_FREQUENCY);
        MerkleProofData[] memory data2 = _aliceAndBob(1 ether, 2 ether);
        bytes32 second = _mintRewards(3 ether, 101, 200, _buildMerkleTree(data2));
        IL1RewardManager.ClaimOrder memory aliceSecond = _claimOrder(second, data2[0], 0);

        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](2);
        claimOrders[0] = aliceFirst;
        claimOrders[1] = aliceSecond;
        l1RewardManager.claimRewards(claimOrders);

        uint256 expected = (6 ether * l1RewardManager.getInterval(first).ethToPufETHRate / 1 ether)
            + (1 ether * l1RewardManager.getInterval(second).ethToPufETHRate / 1 ether);
        assertEq(pufferVault.balanceOf(alice), expected, "each interval uses its own rate");
        assertLt(
            l1RewardManager.getInterval(second).ethToPufETHRate,
            l1RewardManager.getInterval(first).ethToPufETHRate,
            "rate changed"
        );
    }

    function test_claimsNeverTakeFundsOfOtherIntervals() public {
        // First interval is correct
        MerkleProofData[] memory data1 = _aliceAndBob(6 ether, 4 ether);
        bytes32 first = _mintRewards(10 ether, 1, 100, _buildMerkleTree(data1));
        IL1RewardManager.ClaimOrder memory bobFirst = _claimOrder(first, data1[1], 1);

        vm.warp(block.timestamp + MINT_FREQUENCY);

        // Second interval has a wrong root: its leaves add up to more than the minted rewards
        MerkleProofData[] memory data2 = _aliceAndBob(8 ether, 8 ether);
        bytes32 second = _mintRewards(10 ether, 101, 200, _buildMerkleTree(data2));
        IL1RewardManager.ClaimOrder memory aliceSecond = _claimOrder(second, data2[0], 0);
        IL1RewardManager.ClaimOrder memory bobSecond = _claimOrder(second, data2[1], 1);

        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = aliceSecond;
        l1RewardManager.claimRewards(claimOrders);

        // Bob's claim from the wrong interval would use pufETH of the first interval
        claimOrders[0] = bobSecond;
        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.ClaimExceedsIntervalRewards.selector, second));
        l1RewardManager.claimRewards(claimOrders);

        // The first interval is not affected
        claimOrders[0] = bobFirst;
        l1RewardManager.claimRewards(claimOrders);
        assertEq(
            pufferVault.balanceOf(bob),
            4 ether * l1RewardManager.getInterval(first).ethToPufETHRate / 1 ether,
            "bob got the first interval rewards"
        );
    }

    function testRevert_claimRewardsBeforeClaimingDelay() public {
        MerkleProofData[] memory data = _aliceAndBob(6 ether, 4 ether);
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, _buildMerkleTree(data));
        uint256 claimableAt = l1RewardManager.getInterval(intervalId).claimableAt;

        vm.warp(claimableAt - 1);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);

        vm.expectRevert(
            abi.encodeWithSelector(IL1RewardManager.ClaimingLocked.selector, intervalId, alice, claimableAt)
        );
        l1RewardManager.claimRewards(claimOrders);
    }

    function testRevert_claimRewardsTwice() public {
        MerkleProofData[] memory data = _aliceAndBob(6 ether, 4 ether);
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, _buildMerkleTree(data));
        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);
        l1RewardManager.claimRewards(claimOrders);

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.AlreadyClaimed.selector, intervalId, alice));
        l1RewardManager.claimRewards(claimOrders);
    }

    function testRevert_claimRewardsInvalidProof() public {
        MerkleProofData[] memory data = _aliceAndBob(6 ether, 4 ether);
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, _buildMerkleTree(data));
        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);

        // Wrong amount
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);
        claimOrders[0].amount = 7 ether;
        vm.expectRevert(IL1RewardManager.InvalidProof.selector);
        l1RewardManager.claimRewards(claimOrders);

        // Wrong account
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);
        claimOrders[0].account = charlie;
        vm.expectRevert(IL1RewardManager.InvalidProof.selector);
        l1RewardManager.claimRewards(claimOrders);

        // Wrong isL1Contract flag
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);
        claimOrders[0].isL1Contract = true;
        vm.expectRevert(IL1RewardManager.InvalidProof.selector);
        l1RewardManager.claimRewards(claimOrders);

        // Proof of another leaf
        claimOrders[0] = _claimOrder(intervalId, data[0], 1);
        vm.expectRevert(IL1RewardManager.InvalidProof.selector);
        l1RewardManager.claimRewards(claimOrders);
    }

    function testRevert_claimRewardsNonExistingInterval() public {
        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = IL1RewardManager.ClaimOrder({
            intervalId: keccak256("unknown"),
            amount: 1 ether,
            isL1Contract: false,
            account: alice,
            merkleProof: new bytes32[](0)
        });

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.InvalidClaimingInterval.selector, keccak256("unknown")));
        l1RewardManager.claimRewards(claimOrders);
    }

    function testRevert_claimRewardsFrozenInterval() public {
        MerkleProofData[] memory data = _aliceAndBob(6 ether, 4 ether);
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, _buildMerkleTree(data));

        vm.prank(rewardWatcher);
        l1RewardManager.freezeInterval(1, 100);

        vm.warp(block.timestamp + CLAIMING_DELAY);
        assertTrue(l1RewardManager.isClaimingLocked(intervalId), "frozen is locked");

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.IntervalIsFrozen.selector, intervalId));
        l1RewardManager.claimRewards(claimOrders);
    }

    function testRevert_claimRewardsRevertedInterval() public {
        MerkleProofData[] memory data = _aliceAndBob(6 ether, 4 ether);
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, _buildMerkleTree(data));

        vm.prank(DAO);
        l1RewardManager.freezeAndRevertInterval(1, 100);

        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.InvalidClaimingInterval.selector, intervalId));
        l1RewardManager.claimRewards(claimOrders);
    }

    function test_pauseClaimsOnly() public {
        MerkleProofData[] memory data = _aliceAndBob(6 ether, 4 ether);
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, _buildMerkleTree(data));

        // Close only `claimRewards`, so freeze and revert keep working.
        // Closing the whole target would also block freeze and revert.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = L1RewardManager.claimRewards.selector;
        vm.prank(_broadcaster);
        accessManager.setTargetFunctionRole(address(l1RewardManager), selectors, ADMIN_ROLE);

        vm.prank(rewardWatcher);
        l1RewardManager.freezeInterval(1, 100);

        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](1);
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        l1RewardManager.claimRewards(claimOrders);

        vm.prank(DAO);
        l1RewardManager.revertInterval(1, 100);
    }

    function test_freezeInterval() public {
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, keccak256("root"));

        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.IntervalFrozen(intervalId, 1, 100);
        vm.prank(rewardWatcher);
        l1RewardManager.freezeInterval(1, 100);

        assertEq(
            uint256(l1RewardManager.getInterval(intervalId).status),
            uint256(L1RewardManagerStorage.IntervalStatus.FROZEN),
            "frozen"
        );
        assertTrue(l1RewardManager.isClaimingLocked(intervalId), "locked");
    }

    function testRevert_freezeIntervalUnauthorized() public {
        _mintRewards(10 ether, 1, 100, keccak256("root"));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        l1RewardManager.freezeInterval(1, 100);

        // The minter can not freeze its own interval
        vm.prank(rewardsMinter);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, rewardsMinter));
        l1RewardManager.freezeInterval(1, 100);
    }

    function testRevert_freezeIntervalAfterClaimingDelay() public {
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, keccak256("root"));
        vm.warp(l1RewardManager.getInterval(intervalId).claimableAt);

        vm.prank(rewardWatcher);
        vm.expectRevert(IL1RewardManager.UnableToFreezeInterval.selector);
        l1RewardManager.freezeInterval(1, 100);
    }

    function testRevert_freezeIntervalTwice() public {
        _mintRewards(10 ether, 1, 100, keccak256("root"));

        vm.startPrank(rewardWatcher);
        l1RewardManager.freezeInterval(1, 100);

        vm.expectRevert(IL1RewardManager.UnableToFreezeInterval.selector);
        l1RewardManager.freezeInterval(1, 100);
        vm.stopPrank();
    }

    function testRevert_freezeNonExistingInterval() public {
        _mintRewards(10 ether, 1, 100, keccak256("root"));

        vm.prank(rewardWatcher);
        vm.expectRevert(IL1RewardManager.UnableToFreezeInterval.selector);
        l1RewardManager.freezeInterval(1, 99);
    }

    function test_revertInterval() public {
        bytes32 intervalId = _mintRewards(10 ether, 1, 100, keccak256("root"));
        L1RewardManagerStorage.Interval memory interval = l1RewardManager.getInterval(intervalId);

        uint256 totalRewardMintAmountBefore = pufferVault.getTotalRewardMintAmount();
        uint256 totalSupplyBefore = pufferVault.totalSupply();

        vm.prank(rewardWatcher);
        l1RewardManager.freezeInterval(1, 100);

        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.RevertedRewards(10 ether, 1, 100, keccak256("root"));
        vm.prank(DAO);
        l1RewardManager.revertInterval(1, 100);

        assertEq(
            uint256(l1RewardManager.getInterval(intervalId).status),
            uint256(L1RewardManagerStorage.IntervalStatus.REVERTED),
            "reverted"
        );
        assertEq(pufferVault.balanceOf(address(l1RewardManager)), 0, "pufETH burned");
        assertEq(pufferVault.totalSupply(), totalSupplyBefore - interval.pufETHAmount, "supply");
        assertEq(
            pufferVault.getTotalRewardMintAmount(), totalRewardMintAmountBefore - 10 ether, "vault reward mint amount"
        );
        assertEq(l1RewardManager.getCurrentIntervalEndEpoch(), 0, "epoch pointer moved back");
    }

    function testRevert_revertIntervalNotFrozen() public {
        _mintRewards(10 ether, 1, 100, keccak256("root"));

        vm.prank(DAO);
        vm.expectRevert(IL1RewardManager.UnableToRevertInterval.selector);
        l1RewardManager.revertInterval(1, 100);
    }

    function testRevert_revertIntervalUnauthorized() public {
        _mintRewards(10 ether, 1, 100, keccak256("root"));

        vm.startPrank(rewardWatcher);
        l1RewardManager.freezeInterval(1, 100);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, rewardWatcher));
        l1RewardManager.revertInterval(1, 100);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, rewardWatcher));
        l1RewardManager.freezeAndRevertInterval(1, 100);
        vm.stopPrank();
    }

    function testRevert_revertIntervalTwice() public {
        _mintRewards(10 ether, 1, 100, keccak256("root"));

        vm.startPrank(DAO);
        l1RewardManager.freezeAndRevertInterval(1, 100);

        vm.expectRevert(IL1RewardManager.UnableToRevertInterval.selector);
        l1RewardManager.revertInterval(1, 100);

        vm.expectRevert(IL1RewardManager.UnableToFreezeInterval.selector);
        l1RewardManager.freezeAndRevertInterval(1, 100);
        vm.stopPrank();
    }

    function test_mintSameEpochsAgainAfterRevert() public {
        _mintRewards(10 ether, 1, 100, keccak256("wrong root"));
        vm.warp(block.timestamp + MINT_FREQUENCY);
        bytes32 second = _mintRewards(5 ether, 101, 200, keccak256("wrong root 2"));

        vm.prank(DAO);
        l1RewardManager.freezeAndRevertInterval(101, 200);
        assertEq(l1RewardManager.getCurrentIntervalEndEpoch(), 100, "back to the first interval");

        vm.warp(block.timestamp + MINT_FREQUENCY);

        // The corrected interval uses the same epochs, so the same interval ID
        MerkleProofData[] memory data = _aliceAndBob(3 ether, 2 ether);
        bytes32 corrected = _mintRewards(5 ether, 101, 200, _buildMerkleTree(data));
        assertEq(corrected, second, "same interval ID");
        assertEq(
            uint256(l1RewardManager.getInterval(corrected).status),
            uint256(L1RewardManagerStorage.IntervalStatus.ACTIVE),
            "active again"
        );

        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](2);
        claimOrders[0] = _claimOrder(corrected, data[0], 0);
        claimOrders[1] = _claimOrder(corrected, data[1], 1);
        l1RewardManager.claimRewards(claimOrders);

        assertEq(
            l1RewardManager.getInterval(corrected).claimedPufETHAmount,
            pufferVault.balanceOf(alice) + pufferVault.balanceOf(bob),
            "claimed"
        );
    }

    function test_mintOtherEpochsAfterRevert() public {
        _mintRewards(10 ether, 1, 100, keccak256("root"));

        vm.prank(DAO);
        l1RewardManager.freezeAndRevertInterval(1, 100);

        vm.warp(block.timestamp + MINT_FREQUENCY);

        _mintRewards(10 ether, 1, 150, keccak256("root2"));
        assertEq(l1RewardManager.getLastIntervalEndEpoch(), 0, "last end epoch");
        assertEq(l1RewardManager.getCurrentIntervalEndEpoch(), 150, "current end epoch");
    }

    function test_setClaimingDelay() public {
        bytes32 first = _mintRewards(1 ether, 1, 100, keccak256("root"));
        uint256 firstClaimableAt = l1RewardManager.getInterval(first).claimableAt;

        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.ClaimingDelayUpdated(CLAIMING_DELAY, 72 hours);
        vm.prank(DAO);
        l1RewardManager.setClaimingDelay(72 hours);

        assertEq(l1RewardManager.getClaimingDelay(), 72 hours, "delay");
        assertEq(l1RewardManager.getInterval(first).claimableAt, firstClaimableAt, "minted interval keeps its time");

        vm.warp(block.timestamp + MINT_FREQUENCY);
        bytes32 second = _mintRewards(1 ether, 101, 200, keccak256("root2"));
        assertEq(l1RewardManager.getInterval(second).claimableAt, block.timestamp + 72 hours, "new delay is used");
    }

    function testRevert_setClaimingDelay() public {
        vm.startPrank(DAO);
        vm.expectRevert(IL1RewardManager.InvalidClaimingDelay.selector);
        l1RewardManager.setClaimingDelay(6 hours - 1);

        vm.expectRevert(IL1RewardManager.InvalidClaimingDelay.selector);
        l1RewardManager.setClaimingDelay(72 hours + 1);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        l1RewardManager.setClaimingDelay(12 hours);
    }

    function test_setAllowedRewardMintAmount() public {
        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.AllowedRewardMintAmountUpdated(100 ether, 50 ether);
        vm.prank(DAO);
        l1RewardManager.setAllowedRewardMintAmount(50 ether);

        vm.prank(rewardsMinter);
        vm.expectRevert(IL1RewardManager.InvalidMintAmount.selector);
        l1RewardManager.mintRewards(_mintParams(50 ether + 1, 1, 100, keccak256("root")));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        l1RewardManager.setAllowedRewardMintAmount(1 ether);
    }

    function test_setAllowedRewardMintFrequency() public {
        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.AllowedRewardMintFrequencyUpdated(MINT_FREQUENCY, 7 days);
        vm.prank(DAO);
        l1RewardManager.setAllowedRewardMintFrequency(7 days);
        assertEq(_getAllowedRewardMintFrequency(), 7 days, "frequency");

        vm.prank(DAO);
        vm.expectRevert(IL1RewardManager.InvalidMintFrequency.selector);
        l1RewardManager.setAllowedRewardMintFrequency(72 hours - 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        l1RewardManager.setAllowedRewardMintFrequency(7 days);
    }

    function test_merkleWithBackendMockData() public {
        // Same data and root as in the L2RewardManager test: the backend tree format works on L1 without changes
        MerkleProofData[] memory data = new MerkleProofData[](2);
        data[0] =
            MerkleProofData({ account: 0xBDAdFC936FA42Bcc54f39667B1868035290a0241, isL1Contract: false, amount: 6000 });
        data[1] =
            MerkleProofData({ account: 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0, isL1Contract: false, amount: 4000 });

        bytes32 root = _buildMerkleTree(data);
        assertEq(root, bytes32(hex"d084a504e90e7784c62925f1bad75bf96caf2c75d6ed28ec0bd5bc4d1b665652"), "backend root");

        bytes32 intervalId = _mintRewards(10000, 61180, 61190, root);
        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](2);
        claimOrders[0] = _claimOrder(intervalId, data[0], 0);
        claimOrders[1] = _claimOrder(intervalId, data[1], 1);
        l1RewardManager.claimRewards(claimOrders);

        assertTrue(l1RewardManager.isClaimed(intervalId, data[0].account), "claimed 1");
        assertTrue(l1RewardManager.isClaimed(intervalId, data[1].account), "claimed 2");
    }

    function testFuzz_claimsNeverExceedMintedRewards(uint96 amount1, uint96 amount2, uint96 amount3, uint96 extraAssets)
        public
    {
        amount1 = uint96(bound(amount1, 1, 30 ether));
        amount2 = uint96(bound(amount2, 1, 30 ether));
        amount3 = uint96(bound(amount3, 1, 30 ether));

        // Changes the exchange rate
        vm.deal(address(pufferVault), address(pufferVault).balance + bound(extraAssets, 0, 1000 ether));

        MerkleProofData[] memory data = new MerkleProofData[](3);
        data[0] = MerkleProofData({ account: alice, amount: amount1, isL1Contract: false });
        data[1] = MerkleProofData({ account: bob, amount: amount2, isL1Contract: false });
        data[2] = MerkleProofData({ account: charlie, amount: amount3, isL1Contract: true });

        uint256 rewardsAmount = uint256(amount1) + amount2 + amount3;
        bytes32 intervalId = _mintRewards(rewardsAmount, 1, 100, _buildMerkleTree(data));
        vm.warp(block.timestamp + CLAIMING_DELAY);

        IL1RewardManager.ClaimOrder[] memory claimOrders = new IL1RewardManager.ClaimOrder[](3);
        for (uint256 i = 0; i < 3; ++i) {
            claimOrders[i] = _claimOrder(intervalId, data[i], i);
        }
        l1RewardManager.claimRewards(claimOrders);

        L1RewardManagerStorage.Interval memory interval = l1RewardManager.getInterval(intervalId);
        uint256 paid = pufferVault.balanceOf(alice) + pufferVault.balanceOf(bob) + pufferVault.balanceOf(charlie);

        assertEq(interval.claimedPufETHAmount, paid, "claimed amount is tracked");
        assertLe(paid, interval.pufETHAmount, "never more than minted");
        // Rounding leaves at most 1 wei per claim in the contract
        assertLe(interval.pufETHAmount - paid, 3, "dust");
        assertEq(pufferVault.balanceOf(address(l1RewardManager)), interval.pufETHAmount - paid, "contract balance");
    }

    function _mintRewards(uint256 rewardsAmount, uint256 startEpoch, uint256 endEpoch, bytes32 root)
        internal
        returns (bytes32 intervalId)
    {
        vm.prank(rewardsMinter);
        l1RewardManager.mintRewards(_mintParams(rewardsAmount, startEpoch, endEpoch, root));
        return l1RewardManager.getIntervalId(startEpoch, endEpoch);
    }

    function _mintParams(uint256 rewardsAmount, uint256 startEpoch, uint256 endEpoch, bytes32 root)
        internal
        pure
        returns (IL1RewardManager.MintRewardsParams memory)
    {
        return IL1RewardManager.MintRewardsParams({
            rewardsAmount: rewardsAmount,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: root,
            rewardsURI: "uri"
        });
    }

    function _aliceAndBob(uint256 aliceAmount, uint256 bobAmount)
        internal
        view
        returns (MerkleProofData[] memory data)
    {
        data = new MerkleProofData[](2);
        data[0] = MerkleProofData({ account: alice, amount: aliceAmount, isL1Contract: false });
        data[1] = MerkleProofData({ account: bob, amount: bobAmount, isL1Contract: false });
    }

    function _buildMerkleTree(MerkleProofData[] memory data) internal returns (bytes32 root) {
        leaves = new bytes32[](data.length);
        for (uint256 i = 0; i < data.length; ++i) {
            leaves[i] =
                keccak256(bytes.concat(keccak256(abi.encode(data[i].account, data[i].isL1Contract, data[i].amount))));
        }
        root = merkle.getRoot(leaves);
    }

    function _claimOrder(bytes32 intervalId, MerkleProofData memory data, uint256 leafIndex)
        internal
        view
        returns (IL1RewardManager.ClaimOrder memory)
    {
        return IL1RewardManager.ClaimOrder({
            intervalId: intervalId,
            amount: data.amount,
            isL1Contract: data.isL1Contract,
            account: data.account,
            merkleProof: merkle.getProof(leaves, leafIndex)
        });
    }

    /**
     * @dev Writes the frequency directly, without the minimum check of the setter
     */
    function _setAllowedRewardMintFrequencyInStorage(uint104 frequency) internal {
        uint256 slot0 = uint256(vm.load(address(l1RewardManager), REWARD_MANAGER_STORAGE_LOCATION));
        uint256 mask = uint256(type(uint104).max) << 104;
        slot0 = (slot0 & ~mask) | (uint256(frequency) << 104);
        vm.store(address(l1RewardManager), REWARD_MANAGER_STORAGE_LOCATION, bytes32(slot0));
        assertEq(_getAllowedRewardMintFrequency(), frequency, "frequency in storage");
    }

    function _getAllowedRewardMintFrequency() internal view returns (uint256) {
        return _getAllowedRewardMintFrequency(l1RewardManager);
    }

    function _getAllowedRewardMintFrequency(L1RewardManager target) internal view returns (uint256) {
        bytes32 slot0 = vm.load(address(target), REWARD_MANAGER_STORAGE_LOCATION);
        return (uint256(slot0) >> 104) & type(uint104).max;
    }

    /**
     * @dev A proxy that only ran `initialize`, like the mainnet proxy before this upgrade
     */
    function _deployVersion1Proxy() internal returns (L1RewardManager) {
        L1RewardManager impl = new L1RewardManager(address(pufferVault));
        return L1RewardManager(
            address(
                new ERC1967Proxy(address(impl), abi.encodeCall(L1RewardManager.initialize, (address(accessManager))))
            )
        );
    }
}
