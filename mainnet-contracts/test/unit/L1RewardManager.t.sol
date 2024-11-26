// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";
import { IL1RewardManager } from "../../src/interface/IL1RewardManager.sol";
import { L1RewardManager } from "../../src/L1RewardManager.sol";
import { L1RewardManagerStorage } from "../../src/L1RewardManagerStorage.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {
    ROLE_ID_DAO,
    PUBLIC_ROLE,
    ROLE_ID_BRIDGE,
    ROLE_ID_L1_REWARD_MANAGER,
    ROLE_ID_OPERATIONS_PAYMASTER
} from "../../script/Roles.sol";
import { InvalidAddress, Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { GenerateAccessManagerCalldata3 } from "script/AccessManagerMigrations/GenerateAccessManagerCalldata3.s.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

contract L1RewardManagerTest is UnitTestHelper {
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

        vm.startPrank(_broadcaster);
        accessManager.setTargetFunctionRole(address(xpufETH), xpufETHDAOselectors, ROLE_ID_DAO);
        accessManager.setTargetFunctionRole(address(xpufETH), xpufETHselectors, PUBLIC_ROLE);

        bytes memory cd = new GenerateAccessManagerCalldata3().generateL1Calldata(
            address(l1RewardManager), address(connext), address(pufferVault), address(pufferModuleManager)
        );
        (bool s,) = address(accessManager).call(cd);
        require(s, "failed setupAccess GenerateAccessManagerCalldata3");

        vm.label(address(l1RewardManager), "L1RewardManager");

        accessManager.grantRole(ROLE_ID_OPERATIONS_PAYMASTER, address(this), 0);

        vm.stopPrank();

        vm.startPrank(DAO);
        xpufETH.setLockbox(address(lockBox));
        xpufETH.setLimits(address(connext), 1000 ether, 1000 ether);

        L1RewardManagerStorage.BridgeData memory bridgeData =
            L1RewardManagerStorage.BridgeData({ destinationDomainId: 2 });
        l1RewardManager.updateBridgeData(address(connext), bridgeData);

        vm.stopPrank();
        vm.deal(address(this), 300 ether);
        vm.deal(DAO, 300 ether);

        vm.warp(365 days);
    }

    modifier allowedDailyFrequency() {
        vm.startPrank(DAO);
        l1RewardManager.setAllowedRewardMintFrequency(1 days);
        vm.stopPrank();
        _;
    }

    modifier allowMintAmount(uint104 amount) {
        vm.startPrank(DAO);
        l1RewardManager.setAllowedRewardMintAmount(amount);
        vm.stopPrank();
        _;
    }

    function test_Constructor() public {
        new L1RewardManager(address(0), address(0), address(0), address(0));
    }

    function testRevert_updateBridgeDataInvalidBridge() public {
        vm.startPrank(DAO);

        L1RewardManagerStorage.BridgeData memory bridgeData = l1RewardManager.getBridge(address(connext));

        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        l1RewardManager.updateBridgeData(address(0), bridgeData);
    }

    function test_MintAndBridgeRewardsSuccess() public allowedDailyFrequency allowMintAmount(100 ether) {
        rewardsAmount = 100 ether;

        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            bridge: address(connext),
            rewardsAmount: rewardsAmount,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        uint256 initialTotalAssets = pufferVault.totalAssets();

        l1RewardManager.mintAndBridgeRewards(params);

        assertEq(pufferVault.totalAssets(), initialTotalAssets + 100 ether);
    }

    function testRevert_MintAndBridgeRewardsInvalidBridge() public allowedDailyFrequency allowMintAmount(100 ether) {
        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            bridge: address(0), // invalid bridge
            rewardsAmount: 100 ether,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.BridgeNotAllowlisted.selector));
        l1RewardManager.mintAndBridgeRewards(params);
    }

    function test_depositRewardsBackToTheVault() public {
        test_MintAndBridgeRewardsSuccess();

        address module = pufferProtocol.getModuleAddress(PUFFER_MODULE_0);

        // airdrop the rewards amount to the module
        vm.deal(module, rewardsAmount);

        address[] memory modules = new address[](1);
        modules[0] = module;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = rewardsAmount;

        pufferModuleManager.transferRewardsToTheVault(modules, amounts);

        uint256 amount = pufferVault.getTotalRewardMintAmount() - pufferVault.getTotalRewardDepositAmount();

        assertEq(amount, 0, "total rewards amount should be 0");
    }

    // If there is a race condition, where the rewards are deposited to the vault before they are reverted
    // The old coude would panic, this test ensures that the code does not panic
    function test_undoMintAndBridgeRewardsRaceCondition() public allowedDailyFrequency allowMintAmount(100 ether) {
        // Get the initial state
        uint256 assetsBefore = pufferVault.totalAssets();
        uint256 rewardsAmountBefore = pufferVault.getTotalRewardMintAmount();
        uint256 pufETHTotalSupplyBefore = pufferVault.totalSupply();

        // Simulate mintAndBridgeRewards amounts in there are hardcoded to 100 ether
        test_MintAndBridgeRewardsSuccess();

        // Simulate a race condition, where the rewards are deposited to the vault before they are reverted
        address module = pufferProtocol.getModuleAddress(PUFFER_MODULE_0);
        // airdrop the rewards amount to the module
        vm.deal(module, rewardsAmount);
        address[] memory modules = new address[](1);
        modules[0] = module;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = rewardsAmount;
        pufferModuleManager.transferRewardsToTheVault(modules, amounts);

        // Now try tor evert the mintAndBridgeRewards, it panics
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
        deal(address(xpufETH), address(l1RewardManager), 100 ether);

        vm.startPrank(address(connext));

        // Simulate a call from the connext bridge
        l1RewardManager.xReceive(bytes32(0), 0, address(0), address(l2RewardManager), 2, encodedCallData);

        assertEq(pufferVault.totalAssets(), assetsBefore, "assets before and now should match");
        assertEq(
            pufferVault.getTotalRewardMintAmount(), rewardsAmountBefore, "rewards amount before and now should match"
        );
        assertEq(pufferVault.totalSupply(), pufETHTotalSupplyBefore, "total supply before and now should match");
    }

    function test_undoMintAndBridgeRewards() public allowedDailyFrequency allowMintAmount(100 ether) {
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
        deal(address(xpufETH), address(l1RewardManager), 100 ether);

        vm.startPrank(address(connext));

        // Simulate a call from the connext bridge
        l1RewardManager.xReceive(bytes32(0), 0, address(0), address(l2RewardManager), 2, encodedCallData);

        assertEq(pufferVault.totalAssets(), assetsBefore, "assets before and now should match");
        assertEq(
            pufferVault.getTotalRewardMintAmount(), rewardsAmountBefore, "rewards amount before and now should match"
        );
        assertEq(pufferVault.totalSupply(), pufETHTotalSupplyBefore, "total supply before and now should match");
    }

    function testRevert_invalidOriginAddress() public {
        vm.startPrank(address(connext));

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        l1RewardManager.xReceive(bytes32(0), 0, address(0), address(0), 0, "");
    }

    function testRevert_MintAndBridgeRewardsInvalidMintAmount() public {
        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            bridge: address(connext),
            rewardsAmount: 200 ether, // assuming this is more than allowed
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.InvalidMintAmount.selector));
        l1RewardManager.mintAndBridgeRewards(params);
    }

    function test_MintAndBridgeRewardsNotAllowedMintFrequency()
        public
        allowedDailyFrequency
        allowMintAmount(100 ether)
    {
        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            bridge: address(connext),
            rewardsAmount: 1 ether,
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });
        l1RewardManager.mintAndBridgeRewards(params);

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.NotAllowedMintFrequency.selector));
        l1RewardManager.mintAndBridgeRewards(params);
    }

    function test_SetAllowedRewardMintAmountSuccess() public {
        uint88 newAmount = 200 ether;

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.AllowedRewardMintAmountUpdated(0, newAmount);
        l1RewardManager.setAllowedRewardMintAmount(newAmount);

        vm.stopPrank();
    }

    function testRevert_SetAllowedRewardMintAmount() public {
        uint88 newAmount = 200 ether;
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, address(this)));
        l1RewardManager.setAllowedRewardMintAmount(newAmount);
    }

    function test_SetAllowedRewardMintFrequencySuccess() public allowedDailyFrequency {
        uint24 oldFrequency = 1 days;
        uint24 newFrequency = 2 days;

        vm.startPrank(DAO);

        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.AllowedRewardMintFrequencyUpdated(oldFrequency, newFrequency);
        l1RewardManager.setAllowedRewardMintFrequency(newFrequency);
        vm.stopPrank();
    }

    function testRevert_SetAllowedRewardMintFrequency() public {
        uint24 newFrequency = 86400; // 24 hours

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, address(this)));
        l1RewardManager.setAllowedRewardMintFrequency(newFrequency);
    }

    function testRevert_SetInvalidMintFrequency() public {
        vm.startPrank(DAO);

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.InvalidMintFrequency.selector));
        l1RewardManager.setAllowedRewardMintFrequency(1 hours);
    }

    function test_setClaimer() public {
        address newClaimer = address(0x123);

        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.L2RewardClaimerUpdated(address(this), newClaimer);
        l1RewardManager.setL2RewardClaimer(address(connext), newClaimer);
    }

    function testRevert_setClaimerInvalidBrige() public {
        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.BridgeNotAllowlisted.selector));
        l1RewardManager.setL2RewardClaimer(address(0x1111), address(0x123));
    }

    function testRevert_callFromInvalidBridgeOrigin() public {
        vm.startPrank(address(connext));

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        l1RewardManager.xReceive(bytes32(0), 0, address(0), address(l2RewardManager), 4123123, "");
    }

    function test_upgrade_plugin() public {
        Options memory opts;

        opts.constructorData = abi.encode(address(0), address(pufferVault), address(0), address(l2RewardManager));

        address proxy = Upgrades.deployUUPSProxy(
            "L1RewardManager.sol", abi.encodeCall(L1RewardManager.initialize, (address(accessManager))), opts
        );

        vm.startPrank(address(timelock));

        // It should revert because the new implementation is not good
        vm.expectRevert();
        Upgrades.upgradeProxy(proxy, "L1RewardManagerUnsafe.sol:L1RewardManagerUnsafe", "", opts);
    }
}
