// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";
import { IPufferVaultV3 } from "../../src/interface/IPufferVaultV3.sol";
import { PufferVaultV3 } from "../../src/PufferVaultV3.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { ROLE_ID_DAO, PUBLIC_ROLE, ROLE_ID_BRIDGE, ROLE_ID_REWARD_BURNER } from "../../script/Roles.sol";

contract PufferVaultV3Test is UnitTestHelper {
    uint256 rewardsAmount;
    uint256 startEpoch = 1;
    uint256 endEpoch = 2;

    function setUp() public override {
        super.setUp();

        bytes4[] memory xpufETHselectors = new bytes4[](3);
        xpufETHselectors[0] = xPufETH.mint.selector;
        xpufETHselectors[1] = xPufETH.burn.selector;

        bytes4[] memory xpufETHDAOselectors = new bytes4[](2);
        xpufETHDAOselectors[0] = xPufETH.setLimits.selector;
        xpufETHDAOselectors[1] = xPufETH.setLockbox.selector;

        bytes4[] memory pufferVaultSelectors = new bytes4[](1);
        pufferVaultSelectors[0] = IPufferVaultV3.setL2RewardClaimer.selector;

        vm.startPrank(_broadcaster);
        accessManager.setTargetFunctionRole(address(xpufETH), xpufETHDAOselectors, ROLE_ID_DAO);
        accessManager.setTargetFunctionRole(address(xpufETH), xpufETHselectors, PUBLIC_ROLE);
        accessManager.setTargetFunctionRole(address(pufferVault), pufferVaultSelectors, PUBLIC_ROLE);

        accessManager.grantRole(ROLE_ID_DAO, DAO, 0);
        accessManager.grantRole(ROLE_ID_BRIDGE, address(connext), 0);

        bytes4[] memory bridgeSelectors = new bytes4[](1);
        bridgeSelectors[0] = xPufETHBurner.xReceive.selector;
        accessManager.setTargetFunctionRole(address(xPufETHBurner), bridgeSelectors, ROLE_ID_BRIDGE);

        // Burner role
        bytes4[] memory burnerSelectors = new bytes4[](1);
        burnerSelectors[0] = PufferVaultV3.revertBridgingInterval.selector;
        accessManager.setTargetFunctionRole(address(pufferVault), burnerSelectors, ROLE_ID_REWARD_BURNER);

        accessManager.grantRole(ROLE_ID_REWARD_BURNER, address(xPufETHBurner), 0);

        vm.stopPrank();

        vm.startPrank(DAO);
        xpufETH.setLockbox(address(lockBox));
        xpufETH.setLimits(address(connext), 1000 ether, 1000 ether);
        pufferVault.setAllowedRewardMintFrequency(1 days);
        IPufferVaultV3.BridgeData memory bridgeData = IPufferVaultV3.BridgeData({ destinationDomainId: 1 });

        pufferVault.updateBridgeData(address(connext), bridgeData);

        vm.stopPrank();
        vm.deal(address(this), 300 ether);
        vm.deal(DAO, 300 ether);

        vm.warp(365 days);
    }

    function test_MintAndBridgeRewardsSuccess() public {
        rewardsAmount = 100 ether;

        IPufferVaultV3.MintAndBridgeParams memory params = IPufferVaultV3.MintAndBridgeParams({
            bridge: address(connext),
            rewardsAmount: rewardsAmount,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        uint256 initialTotalAssets = pufferVault.totalAssets();

        vm.startPrank(DAO);

        pufferVault.setAllowedRewardMintAmount(100 ether);
        pufferVault.mintAndBridgeRewards(params);

        assertEq(pufferVault.totalAssets(), initialTotalAssets + 100 ether);
        vm.stopPrank();
    }

    function test_undoMintAndBridgeRewards() public {
        // Get the initial state
        uint256 assetsBefore = pufferVault.totalAssets();
        uint256 rewardsAmountBefore = pufferVault.getTotalRewardMintAmount();
        uint256 pufETHTotalSupplyBefore = pufferVault.totalSupply();

        // Simulate mintAndBridgeRewards amounts in there are hardcoded to 100 ether
        test_MintAndBridgeRewardsSuccess();

        // Rewards and assets increase
        assertEq(pufferVault.totalAssets(), assetsBefore + 100 ether, "assets before and now should match");
        assertEq(
            pufferVault.getTotalRewardMintAmount(),
            rewardsAmountBefore + 100 ether,
            "rewards amount before and now should match"
        );
        assertEq(
            pufferVault.totalSupply(), pufETHTotalSupplyBefore + 100 ether, "total supply before and now should match"
        );

        L2RewardManagerStorage.EpochRecord memory epochRecord = L2RewardManagerStorage.EpochRecord({
            startEpoch: uint72(startEpoch),
            endEpoch: uint72(endEpoch),
            timeBridged: uint48(block.timestamp),
            ethToPufETHRate: 1 ether,
            pufETHAmount: 100 ether,
            ethAmount: 100 ether,
            rewardRoot: bytes32(hex"aabb")
        });

        bytes memory encodedCallData = abi.encode(epochRecord);

        // airdrop rewardsAmount to burner
        deal(address(xpufETH), address(xPufETHBurner), 100 ether);

        vm.startPrank(address(connext));

        // Simulate a call from the connext bridge
        xPufETHBurner.xReceive(bytes32(0), 0, address(0), address(l2RewardsManagerMock), 0, encodedCallData);

        assertEq(pufferVault.totalAssets(), assetsBefore, "assets before and now should match");
        assertEq(
            pufferVault.getTotalRewardMintAmount(), rewardsAmountBefore, "rewards amount before and now should match"
        );
        assertEq(pufferVault.totalSupply(), pufETHTotalSupplyBefore, "total supply before and now should match");
    }

    function testRevert_MintAndBridgeRewardsInvalidMintAmount() public {
        IPufferVaultV3.MintAndBridgeParams memory params = IPufferVaultV3.MintAndBridgeParams({
            bridge: address(connext),
            rewardsAmount: 200 ether, // assuming this is more than allowed
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        vm.startPrank(DAO);

        vm.expectRevert(abi.encodeWithSelector(IPufferVaultV3.InvalidMintAmount.selector));
        pufferVault.mintAndBridgeRewards(params);
        vm.stopPrank();
    }

    function test_MintAndBridgeRewardsNotAllowedMintFrequency() public {
        IPufferVaultV3.MintAndBridgeParams memory params = IPufferVaultV3.MintAndBridgeParams({
            bridge: address(connext),
            rewardsAmount: 1 ether,
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        vm.startPrank(DAO);

        pufferVault.setAllowedRewardMintAmount(2 ether);
        pufferVault.mintAndBridgeRewards(params);

        vm.expectRevert(abi.encodeWithSelector(IPufferVaultV3.NotAllowedMintFrequency.selector));
        pufferVault.mintAndBridgeRewards(params);
        vm.stopPrank();
    }

    function test_SetAllowedRewardMintAmountSuccess() public {
        uint88 newAmount = 200 ether;
        vm.startPrank(DAO);

        vm.expectEmit(true, true, true, true);
        emit IPufferVaultV3.AllowedRewardMintAmountUpdated(0, newAmount);
        pufferVault.setAllowedRewardMintAmount(newAmount);

        vm.stopPrank();
    }

    function testRevert_SetAllowedRewardMintAmount() public {
        uint88 newAmount = 200 ether;
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, address(this)));
        pufferVault.setAllowedRewardMintAmount(newAmount);
    }

    function testSetAllowedRewardMintFrequencySuccess() public {
        uint24 oldFrequency = 1 days;
        uint24 newFrequency = 2 days;

        vm.startPrank(DAO);

        vm.expectEmit(true, true, true, true);
        emit IPufferVaultV3.AllowedRewardMintFrequencyUpdated(oldFrequency, newFrequency);
        pufferVault.setAllowedRewardMintFrequency(newFrequency);
        vm.stopPrank();
    }

    function testRevert_SetAllowedRewardMintFrequency() public {
        uint24 newFrequency = 86400; // 24 hours

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, address(this)));
        pufferVault.setAllowedRewardMintFrequency(newFrequency);
    }

    function testSetClaimerRevert() public {
        address newClaimer = address(0x123);

        vm.expectEmit(true, true, true, true);
        emit IPufferVaultV3.L2RewardClaimerUpdated(address(this), newClaimer);
        pufferVault.setL2RewardClaimer(address(connext), newClaimer);
    }
}
