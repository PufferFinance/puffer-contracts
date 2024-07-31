// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { IPufferVaultV3 } from "../../src/interface/IPufferVaultV3.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { ROLE_ID_DAO, PUBLIC_ROLE, ROLE_ID_BRIDGE, ROLE_ID_GUARDIANS } from "../../script/Roles.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PufferVaultV3Test is UnitTestHelper {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
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

        bytes4[] memory gaurdianSelectors = new bytes4[](1);
        gaurdianSelectors[0] = IPufferVaultV3.mintAndBridgeRewards.selector;

        vm.startPrank(_broadcaster);
        accessManager.setTargetFunctionRole(address(xpufETH), xpufETHDAOselectors, ROLE_ID_DAO);
        // TODO: should this be open to public?
        accessManager.setTargetFunctionRole(address(xpufETH), xpufETHselectors, PUBLIC_ROLE);
        accessManager.setTargetFunctionRole(address(pufferVault), pufferVaultSelectors, PUBLIC_ROLE);
        accessManager.setTargetFunctionRole(address(pufferVault), gaurdianSelectors, ROLE_ID_GUARDIANS);

        accessManager.grantRole(ROLE_ID_DAO, DAO, 0);
        accessManager.grantRole(ROLE_ID_GUARDIANS, guardian1, 0);

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
        uint256 aliceAmount = 0.01308 ether;
        uint256 rewardsAmount = aliceAmount + 0.013 ether + 1 ether;
        uint256 ethToPufETHRate = pufferVault.convertToShares(1 ether);

        IPufferVaultV3.MintAndBridgeParams memory params = IPufferVaultV3.MintAndBridgeParams({
            bridge: address(connext),
            rewardsAmount: rewardsAmount,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: bytes32("root"),
            rewardsURI: "uri"
        });

        uint256 initialTotalAssets = pufferVault.totalAssets();

        vm.startPrank(DAO);

        pufferVault.setAllowedRewardMintAmount(100 ether);
        vm.stopPrank();
        vm.startPrank(guardian1);

        assertEq(IERC20(pufferVault).balanceOf(address(lockBox)), 0, "vault should have 0 pufETH before minting");
        vm.expectEmit();
        emit IPufferVaultV3.MintedAndBridgedRewards(
            rewardsAmount, startEpoch, endEpoch, bytes32("root"), ethToPufETHRate, "uri"
        );

        pufferVault.mintAndBridgeRewards(params);

        assertEq(pufferVault.totalAssets(), initialTotalAssets + rewardsAmount);

        assertEq(IERC20(xpufETH).balanceOf(address(this)), 0, "vault should have 0 xPufETH as it was bridged");
        assertEq(IERC20(xpufETH).balanceOf(address(l2)), 0, "vault should have 0 xPufETH as it was bridged");
        assertEq(IERC20(xpufETH).balanceOf(address(lockBox)), 0, "lockbox should have 0 xPufETH");
        assertEq(
            IERC20(pufferVault).balanceOf(address(lockBox)), rewardsAmount, "vault should have rewardsAmount pufETH"
        );

        // TODO: check for l2RewardManager should have rewardsAmount xPufETH received
        // CANT FIND l2RewardManager in the deployment here, how are we initializing the PufferVaultV3 ? :(

        vm.stopPrank();
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
