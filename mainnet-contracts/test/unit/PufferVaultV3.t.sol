// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { IPufferVaultV3 } from "../../src/interface/IPufferVaultV3.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { ROLE_ID_DAO, ROLE_ID_LOCKBOX } from "../../script/Roles.sol";

contract PufferVaultV3Test is UnitTestHelper {
    function setUp() public override {
        super.setUp();

        bytes4[] memory xpufETHselectors = new bytes4[](3);
        xpufETHselectors[0] = xPufETH.mint.selector;
        xpufETHselectors[1] = xPufETH.burn.selector;

        bytes4[] memory xpufETHDAOselectors = new bytes4[](2);
        xpufETHDAOselectors[0] = xPufETH.setLimits.selector;
        xpufETHDAOselectors[1] = xPufETH.setLockbox.selector;

        vm.startPrank(_broadcaster);
        accessManager.setTargetFunctionRole(address(xpufETH), xpufETHDAOselectors, ROLE_ID_DAO);
        accessManager.setTargetFunctionRole(address(xpufETH), xpufETHselectors, ROLE_ID_LOCKBOX);

        accessManager.grantRole(ROLE_ID_DAO, DAO, 0);
        accessManager.grantRole(ROLE_ID_LOCKBOX, address(lockBox), 0);

        vm.stopPrank();

        vm.startPrank(DAO);
        xpufETH.setLockbox(address(lockBox));
        xpufETH.setLimits(address(connext), 1000 ether, 1000 ether);
        pufferVault.setAllowedRewardMintFrequency(1 days);

        vm.stopPrank();
        vm.deal(address(this), 300 ether);
        vm.deal(DAO, 300 ether);

        vm.warp(365 days);
    }

    function testMintAndBridgeRewardsSuccess() public {
        IPufferVaultV3.BridgingParams memory params = IPufferVaultV3.BridgingParams({
            rewardsAmount: 100 ether,
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        uint256 initialTotalAssets = pufferVault.totalAssets();

        vm.startPrank(DAO);

        pufferVault.setAllowedRewardMintAmount(100 ether);
        pufferVault.mintAndBridgeRewards{ value: 1 ether }(params);

        assertEq(pufferVault.totalAssets(), initialTotalAssets + 100 ether);
        vm.stopPrank();
    }

    function testMintAndBridgeRewardsInvalidMintAmount() public {
        IPufferVaultV3.BridgingParams memory params = IPufferVaultV3.BridgingParams({
            rewardsAmount: 200 ether, // assuming this is more than allowed
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        vm.startPrank(DAO);

        vm.expectRevert(abi.encodeWithSelector(IPufferVaultV3.InvalidMintAmount.selector));
        pufferVault.mintAndBridgeRewards{ value: 1 ether }(params);
        vm.stopPrank();
    }

    function testMintAndBridgeRewardsNotAllowedMintFrequency() public {
        IPufferVaultV3.BridgingParams memory params = IPufferVaultV3.BridgingParams({
            rewardsAmount: 1 ether,
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        vm.startPrank(DAO);

        pufferVault.setAllowedRewardMintAmount(2 ether);
        pufferVault.mintAndBridgeRewards{ value: 1 ether }(params);

        vm.expectRevert(abi.encodeWithSelector(IPufferVaultV3.NotAllowedMintFrequency.selector));
        pufferVault.mintAndBridgeRewards{ value: 1 ether }(params);
        vm.stopPrank();
    }

    function testSetAllowedRewardMintAmountSuccess() public {
        uint88 newAmount = 200 ether;
        vm.startPrank(DAO);

        vm.expectEmit(true, true, true, true);
        emit IPufferVaultV3.AllowedRewardMintAmountUpdated(0, newAmount);
        pufferVault.setAllowedRewardMintAmount(newAmount);

        vm.stopPrank();
    }

    function testSetAllowedRewardMintAmountRevert() public {
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

    function testSetAllowedRewardMintFrequencyRevert() public {
        uint24 newFrequency = 86400; // 24 hours

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, address(this)));
        pufferVault.setAllowedRewardMintFrequency(newFrequency);
    }
}
