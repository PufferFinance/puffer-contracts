// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { L2RewardManager } from "../../src/L2RewardManager.sol";
import { IL2RewardManager } from "../../src/interface/IL2RewardManager.sol";
import { L2RewardManagerStorage } from "../../src/L2RewardManagerStorage.sol";
import { L1RewardManagerStorage } from "mainnet-contracts/src/L1RewardManagerStorage.sol";
import { IL1RewardManager } from "mainnet-contracts/src/interface/IL1RewardManager.sol";
import { L1RewardManager } from "mainnet-contracts/src/L1RewardManager.sol";
import { InvalidAmount, InvalidAddress } from "mainnet-contracts/src/Errors.sol";
import { ERC20Mock } from "mainnet-contracts/test/mocks/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { BridgeMock } from "../mocks/BridgeMock.sol";
import { Merkle } from "murky/Merkle.sol";
import { ROLE_ID_BRIDGE, PUBLIC_ROLE, ROLE_ID_REWARD_WATCHER } from "mainnet-contracts/script/Roles.sol";
import { XERC20Lockbox } from "mainnet-contracts/src/XERC20Lockbox.sol";
import { xPufETH } from "mainnet-contracts/src/l2/xPufETH.sol";
import { ERC20Mock } from "mainnet-contracts/test/mocks/ERC20Mock.sol";
import { NoImplementation } from "mainnet-contracts/src/NoImplementation.sol";

contract PufferVaultMock is ERC20Mock {
    constructor() ERC20Mock("VaultMock", "pufETH") { }

    function mintRewards(uint256 rewardsAmount) external { }

    function revertMintRewards(uint256 pufETHAmount, uint256 ethAmount) external { }
}

/**
 * forge test --match-path test/unit/L2RewardManager.t.sol -vvvv
 */
contract L2RewardManagerTest is Test {
    struct MerkleProofData {
        address account;
        uint256 startEpoch;
        uint256 endEpoch;
        uint256 amount;
    }

    BridgeMock public mockBridge;

    Merkle rewardsMerkleProof;
    bytes32[] rewardsMerkleProofData;

    AccessManager accessManager;
    // 3 validators got the rewards
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    uint256 startEpoch = 1;
    uint256 endEpoch = 2;
    uint256 rewardsAmount;
    uint256 ethToPufETHRate;
    bytes32 rewardsRoot;
    uint256 amountAdjustedForExchangeRate;

    L1RewardManager l1RewardManager;
    XERC20Lockbox xERC20Lockbox;
    PufferVaultMock pufferVault;

    xPufETH xPufETHProxy;

    address l1RewardManagerProxy;
    address l2RewardManagerProxy;
    L2RewardManager public l2RewardManager;

    function setUp() public {
        accessManager = new AccessManager(address(this));

        // Deploy the BridgeMock contract
        mockBridge = new BridgeMock();
        // Deploy the MockERC20 token

        xPufETH xpufETHImplementation = new xPufETH();

        pufferVault = new PufferVaultMock();

        address noImpl = address(new NoImplementation());

        // Deploy empty proxy
        l1RewardManagerProxy = address(new ERC1967Proxy(noImpl, ""));
        l1RewardManager = L1RewardManager(address(l1RewardManagerProxy));
        vm.label(address(l1RewardManager), "l1RewardManagerProxy");

        xPufETHProxy = xPufETH(
            address(
                new ERC1967Proxy{ salt: bytes32("xPufETH") }(
                    address(xpufETHImplementation), abi.encodeCall(xPufETH.initialize, (address(accessManager)))
                )
            )
        );
        vm.label(address(xPufETHProxy), "xPufETHProxy");

        xPufETHProxy.setLimits(address(mockBridge), type(uint104).max, type(uint104).max);

        bytes4[] memory lockBoxSelectors = new bytes4[](2);
        lockBoxSelectors[0] = xPufETH.mint.selector;
        lockBoxSelectors[1] = xPufETH.burn.selector;
        accessManager.setTargetFunctionRole(address(xPufETHProxy), lockBoxSelectors, accessManager.PUBLIC_ROLE());

        // Deploy the lockbox
        xERC20Lockbox = new XERC20Lockbox({ xerc20: address(xPufETHProxy), erc20: address(pufferVault) });

        xPufETHProxy.setLockbox(address(xERC20Lockbox));

        address l2RewardManagerImpl = address(new L2RewardManager(address(xPufETHProxy), address(l1RewardManager)));

        l2RewardManager = L2RewardManager(
            address(
                new ERC1967Proxy(
                    address(l2RewardManagerImpl), abi.encodeCall(L2RewardManager.initialize, (address(accessManager)))
                )
            )
        );

        vm.label(address(l2RewardManager), "l2RewardManagerProxy");

        // L1RewardManager
        L1RewardManager l1RewardManagerImpl = new L1RewardManager({
            XpufETH: address(xPufETHProxy),
            pufETH: address(pufferVault),
            lockbox: address(xERC20Lockbox),
            l2RewardsManager: address(l2RewardManager)
        });

        UUPSUpgradeable(address(l1RewardManagerProxy)).upgradeToAndCall(
            address(l1RewardManagerImpl), abi.encodeCall(L1RewardManager.initialize, (address(accessManager)))
        );

        bytes[] memory calldatas = new bytes[](6);
        bytes4[] memory bridgeSelectors = new bytes4[](1);
        bridgeSelectors[0] = IL2RewardManager.xReceive.selector;
        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(l2RewardManager), bridgeSelectors, ROLE_ID_BRIDGE
        );

        bytes4[] memory publicSelectors = new bytes4[](1);
        publicSelectors[0] = IL2RewardManager.claimRewards.selector;
        calldatas[1] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(l2RewardManager), publicSelectors, PUBLIC_ROLE
        );

        calldatas[2] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_BRIDGE, address(mockBridge), 0);

        bytes4[] memory rewardsWatcherSelectors = new bytes4[](3);
        rewardsWatcherSelectors[0] = L2RewardManager.freezeAndRevertInterval.selector;
        rewardsWatcherSelectors[1] = L2RewardManager.freezeClaimingForInterval.selector;
        rewardsWatcherSelectors[2] = L2RewardManager.revertInterval.selector;
        calldatas[3] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            address(l2RewardManager),
            rewardsWatcherSelectors,
            ROLE_ID_REWARD_WATCHER
        );

        calldatas[4] =
            abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_REWARD_WATCHER, address(this), 0);

        calldatas[5] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(l1RewardManager), bridgeSelectors, ROLE_ID_BRIDGE
        );

        vm.label(address(l1RewardManager), "l1RewardManagerProxy");

        accessManager.multicall(calldatas);
    }

    function test_updateBridgeData() public {
        L2RewardManagerStorage.BridgeData memory bridgeData =
            L2RewardManagerStorage.BridgeData({ destinationDomainId: 1 });

        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        l2RewardManager.updateBridgeData(address(0), bridgeData);

        l2RewardManager.updateBridgeData(address(mockBridge), bridgeData);
    }

    function test_freezeInvalidInterval() public {
        // Allowlist bridge
        test_updateBridgeData();

        // Non existing interval
        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.UnableToFreezeInterval.selector));
        l2RewardManager.freezeAndRevertInterval(address(mockBridge), 123124, 523523);

        test_MintAndBridgeRewardsSuccess();

        vm.warp(block.timestamp + 1 days);
        // Unlock the interval
        assertEq(l2RewardManager.isClaimingLocked(startEpoch, endEpoch), false, "claiming should be unlocked");

        // We cant revert, because the interval is unlocked
        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.UnableToFreezeInterval.selector));
        l2RewardManager.freezeAndRevertInterval(address(mockBridge), startEpoch, endEpoch);
    }

    function test_freezeAndRevertInterval() public {
        // Allowlist bridge
        test_updateBridgeData();

        test_MintAndBridgeRewardsSuccess();

        deal(address(pufferVault), address(xERC20Lockbox), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit IL2RewardManager.ClaimingIntervalReverted(startEpoch, endEpoch, rewardsAmount, rewardsRoot);
        l2RewardManager.freezeAndRevertInterval(address(mockBridge), startEpoch, endEpoch);
    }

    function test_freezeInterval() public {
        test_MintAndBridgeRewardsSuccess();

        assertTrue(l2RewardManager.isClaimingLocked(startEpoch, endEpoch), "claiming should be locked");

        L2RewardManagerStorage.EpochRecord memory epochRecord = l2RewardManager.getEpochRecord(startEpoch, endEpoch);
        assertEq(epochRecord.startEpoch, startEpoch, "startEpoch should be stored in storage correctly");
        assertEq(epochRecord.endEpoch, endEpoch, "endEpoch should be stored in storage correctly");
        assertEq(epochRecord.timeBridged, block.timestamp, "timeBridged should be stored in storage correctly");

        // Freezing the interval sets the timeBridged to 0, making that interval unclaimable
        vm.expectEmit(true, true, true, true);
        emit IL2RewardManager.ClaimingIntervalFrozen(startEpoch, endEpoch);
        l2RewardManager.freezeClaimingForInterval(startEpoch, endEpoch);

        epochRecord = l2RewardManager.getEpochRecord(startEpoch, endEpoch);
        assertEq(epochRecord.timeBridged, 0, "timeBridged should be zero");

        assertTrue(l2RewardManager.isClaimingLocked(startEpoch, endEpoch), "claiming should stay locked");
    }

    function test_revertInterval() public {
        test_updateBridgeData();
        test_freezeInterval();

        // Airdrop rewards to the lockbox so that it doesn't revert
        deal(address(pufferVault), address(xERC20Lockbox), 100 ether);
        l2RewardManager.revertInterval(address(mockBridge), startEpoch, endEpoch);
    }

    function test_setDelayPeriod() public {
        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.InvalidDelayPeriod.selector));
        l2RewardManager.setDelayPeriod(1 hours);

        uint256 delayPeriod = 2 days;
        l2RewardManager.setDelayPeriod(delayPeriod);
        assertEq(l2RewardManager.getClaimingDelay(), delayPeriod, "Claiming delay should be set correctly");
    }

    function test_handleSetClaimer(address claimer) public {
        vm.assume(claimer != address(0));

        // Assume that Alice calls setClaimer on L1
        L1RewardManagerStorage.SetClaimerParams memory params =
            L1RewardManagerStorage.SetClaimerParams({ account: alice, claimer: claimer });

        IL1RewardManager.BridgingParams memory bridgingParams = IL1RewardManager.BridgingParams({
            bridgingType: IL1RewardManager.BridgingType.SetClaimer,
            data: abi.encode(params)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(address(l1RewardManager));

        vm.expectEmit();
        emit IL2RewardManager.ClaimerSet(alice, claimer);
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETHProxy),
            address(this),
            rewardsAmount,
            uint256(0),
            encodedCallData
        );
        vm.stopPrank();
    }

    function test_claimerGetsTheRewards(address claimer) public {
        vm.assume(claimer != alice);
        vm.assume(claimer != address(xPufETHProxy));
        vm.assume(claimer != address(l2RewardManager));

        test_handleSetClaimer(claimer);

        uint256 aliceAmount = 0.01308 ether;

        // Build a merkle proof
        MerkleProofData[] memory merkleProofDatas = new MerkleProofData[](3);
        merkleProofDatas[0] =
            MerkleProofData({ account: alice, startEpoch: startEpoch, endEpoch: endEpoch, amount: aliceAmount });
        merkleProofDatas[1] =
            MerkleProofData({ account: bob, startEpoch: startEpoch, endEpoch: endEpoch, amount: 0.013 ether });
        merkleProofDatas[2] =
            MerkleProofData({ account: charlie, startEpoch: startEpoch, endEpoch: endEpoch, amount: 1 ether });

        rewardsAmount = aliceAmount + 0.013 ether + 1 ether;

        // Airdrop the rewards to the L2RewardManager
        deal(address(xPufETHProxy), address(l2RewardManager), rewardsAmount);

        // For simplicity we assume the exchange rate is 1:1
        ethToPufETHRate = 1 ether;

        rewardsRoot = _buildMerkleProof(merkleProofDatas);

        // Post the rewards root
        L1RewardManagerStorage.MintAndBridgeData memory bridgingCalldata = L1RewardManagerStorage.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IL1RewardManager.BridgingParams memory bridgingParams = IL1RewardManager.BridgingParams({
            bridgingType: IL1RewardManager.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(address(l1RewardManager));
        deal(address(xPufETHProxy), address(l1RewardManager), rewardsAmount);
        xPufETHProxy.approve(address(mockBridge), rewardsAmount);

        vm.expectEmit();
        emit IL2RewardManager.RewardRootAndRatePosted(rewardsAmount, ethToPufETHRate, startEpoch, endEpoch, rewardsRoot);
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETHProxy),
            address(this),
            rewardsAmount,
            uint256(0),
            encodedCallData
        );

        // try to claim right away. It should revert the delay period is not passed

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = aliceAmount;

        bytes32[][] memory aliceProofs = new bytes32[][](1);
        aliceProofs[0] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 0);

        assertEq(xPufETHProxy.balanceOf(claimer), 0, "Claimer should start with zero balance");

        IL2RewardManager.ClaimOrder[] memory claimOrders = new IL2RewardManager.ClaimOrder[](1);
        claimOrders[0] = IL2RewardManager.ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: alice,
            amount: amounts[0],
            merkleProof: aliceProofs[0]
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IL2RewardManager.ClaimingLocked.selector,
                startEpoch,
                endEpoch,
                alice,
                (block.timestamp + l2RewardManager.getClaimingDelay())
            )
        );
        l2RewardManager.claimRewards(claimOrders);

        // fast forward
        vm.warp(block.timestamp + 5 days);

        vm.expectEmit();
        emit IL2RewardManager.Claimed(alice, claimer, startEpoch, endEpoch, aliceAmount);
        l2RewardManager.claimRewards(claimOrders);
        assertEq(xPufETHProxy.balanceOf(claimer), aliceAmount, "alice should end with 0.01308 xpufETH");
        assertEq(xPufETHProxy.balanceOf(alice), 0, "alice should end with 0 xpufETH");
    }

    function test_MintAndBridgeRewardsSuccess() public {
        rewardsAmount = 100 ether;
        ethToPufETHRate = 1 ether;
        rewardsRoot = keccak256(abi.encodePacked("testRoot"));

        L1RewardManagerStorage.MintAndBridgeData memory bridgingCalldata = L1RewardManagerStorage.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IL1RewardManager.BridgingParams memory bridgingParams = IL1RewardManager.BridgingParams({
            bridgingType: IL1RewardManager.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(address(l1RewardManager));

        deal(address(xPufETHProxy), address(l1RewardManager), rewardsAmount);
        xPufETHProxy.approve(address(mockBridge), rewardsAmount);

        vm.expectEmit();
        emit IL2RewardManager.RewardRootAndRatePosted(rewardsAmount, ethToPufETHRate, startEpoch, endEpoch, rewardsRoot);
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETHProxy),
            address(this),
            rewardsAmount,
            uint256(0),
            encodedCallData
        );
        vm.stopPrank();

        L2RewardManagerStorage.EpochRecord memory epochRecord = l2RewardManager.getEpochRecord(startEpoch, endEpoch);
        assertEq(epochRecord.ethToPufETHRate, ethToPufETHRate, "ethToPufETHRate should be stored in storage correctly");
        assertEq(epochRecord.rewardRoot, rewardsRoot, "rewardsRoot should be stored in storage correctly");
    }

    function testRevert_MintAndBridgeRewardsInvalidAmount() public {
        rewardsAmount = 100 ether;
        ethToPufETHRate = 1 ether;
        rewardsRoot = keccak256(abi.encodePacked("testRoot"));

        L1RewardManagerStorage.MintAndBridgeData memory bridgingCalldata = L1RewardManagerStorage.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IL1RewardManager.BridgingParams memory bridgingParams = IL1RewardManager.BridgingParams({
            bridgingType: IL1RewardManager.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(address(l1RewardManager));

        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector));
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETHProxy),
            address(this),
            0 ether, // invalid amount transfered
            uint256(0),
            encodedCallData
        );
    }

    function test_merkleWithBackendMockData() public {
        startEpoch = 61180;
        endEpoch = 61190;

        address noOp1 = 0xBDAdFC936FA42Bcc54f39667B1868035290a0241;
        address noOp2 = 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;

        MerkleProofData[] memory merkleProofDatas = new MerkleProofData[](2);
        merkleProofDatas[0] =
            MerkleProofData({ account: noOp1, startEpoch: startEpoch, endEpoch: endEpoch, amount: 6000 });
        merkleProofDatas[1] =
            MerkleProofData({ account: noOp2, startEpoch: startEpoch, endEpoch: endEpoch, amount: 4000 });

        rewardsRoot = _buildMerkleProof(merkleProofDatas);

        assertEq(
            rewardsRoot,
            bytes32(hex"164fd266b4897088f1548c40c63164ffbb7dab815ff65cee3888fcba59b31343"),
            "Root should be correct"
        );
    }

    function test_claimRewardsAllCases() public {
        // Build a merkle proof for that
        MerkleProofData[] memory merkleProofDatas = new MerkleProofData[](3);
        merkleProofDatas[0] =
            MerkleProofData({ account: alice, startEpoch: startEpoch, endEpoch: endEpoch, amount: 0.01308 ether });
        merkleProofDatas[1] =
            MerkleProofData({ account: bob, startEpoch: startEpoch, endEpoch: endEpoch, amount: 0.013 ether });
        merkleProofDatas[2] =
            MerkleProofData({ account: charlie, startEpoch: startEpoch, endEpoch: endEpoch, amount: 1 ether });

        rewardsAmount = 0.01308 ether + 0.013 ether + 1 ether;

        deal(address(xPufETHProxy), address(l2RewardManager), rewardsAmount);

        ethToPufETHRate = 1 ether;
        rewardsRoot = _buildMerkleProof(merkleProofDatas);

        // Post the rewards root
        L1RewardManagerStorage.MintAndBridgeData memory bridgingCalldata = L1RewardManagerStorage.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IL1RewardManager.BridgingParams memory bridgingParams = IL1RewardManager.BridgingParams({
            bridgingType: IL1RewardManager.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(address(l1RewardManager));

        deal(address(xPufETHProxy), address(l1RewardManager), rewardsAmount);
        xPufETHProxy.approve(address(mockBridge), rewardsAmount);

        vm.expectEmit();
        emit IL2RewardManager.RewardRootAndRatePosted(rewardsAmount, ethToPufETHRate, startEpoch, endEpoch, rewardsRoot);
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETHProxy),
            address(this),
            rewardsAmount,
            uint256(0),
            encodedCallData
        );

        vm.warp(block.timestamp + 5 days);

        L2RewardManagerStorage.EpochRecord memory epochRecord = l2RewardManager.getEpochRecord(startEpoch, endEpoch);
        assertEq(epochRecord.ethToPufETHRate, ethToPufETHRate, "ethToPufETHRate should be stored in storage correctly");
        assertEq(epochRecord.rewardRoot, rewardsRoot, "rewardsRoot should be stored in storage correctly");

        // Claim the rewards
        // Alice amount
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.01308 ether;

        bytes32[][] memory aliceProofs = new bytes32[][](1);
        aliceProofs[0] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 0);

        assertEq(xPufETHProxy.balanceOf(alice), 0, "alice should start with zero balance");

        vm.startPrank(alice);

        IL2RewardManager.ClaimOrder[] memory claimOrders = new IL2RewardManager.ClaimOrder[](1);
        claimOrders[0] = IL2RewardManager.ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: alice,
            amount: amounts[0],
            merkleProof: aliceProofs[0]
        });

        vm.expectEmit();
        emit IL2RewardManager.Claimed(alice, alice, startEpoch, endEpoch, amounts[0]);
        l2RewardManager.claimRewards(claimOrders);
        assertEq(xPufETHProxy.balanceOf(alice), 0.01308 ether, "alice should end with 0.01308 xpufETH");

        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.AlreadyClaimed.selector, startEpoch, endEpoch, alice));
        l2RewardManager.claimRewards(claimOrders);

        // Bob amount
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.AlreadyClaimed.selector, startEpoch, endEpoch, alice));
        l2RewardManager.claimRewards(claimOrders);

        bytes32[][] memory bobProofs = new bytes32[][](1);
        bobProofs[0] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 1);
        bytes32[][] memory charlieProofs = new bytes32[][](1);
        charlieProofs[0] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 2);

        // Mutate amounts, set Charlie's amount
        amounts[0] = 1 ether;
        // Bob claiming with Charlie's prof (charlie did not claim yet)
        // It will revert with InvalidProof because the proof is not valid for bob

        claimOrders[0] = IL2RewardManager.ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: bob,
            amount: amounts[0],
            merkleProof: charlieProofs[0]
        });
        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.InvalidProof.selector));
        l2RewardManager.claimRewards(claimOrders);

        assertEq(xPufETHProxy.balanceOf(charlie), 0, "charlie should start with zero balance");
        // Bob claiming for charlie (bob is msg.sender)
        claimOrders[0] = IL2RewardManager.ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: charlie,
            amount: amounts[0],
            merkleProof: charlieProofs[0]
        });
        l2RewardManager.claimRewards(claimOrders);
        assertEq(xPufETHProxy.balanceOf(charlie), 1 ether, "charlie should end with 1 xpufETH");

        // Mutate amounts, set back Bob's amount
        amounts[0] = 0.013 ether;
        assertEq(xPufETHProxy.balanceOf(bob), 0, "bob should start with zero balance");
        // Bob claiming with his proof
        claimOrders[0] = IL2RewardManager.ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: bob,
            amount: amounts[0],
            merkleProof: bobProofs[0]
        });
        l2RewardManager.claimRewards(claimOrders);
        assertEq(xPufETHProxy.balanceOf(bob), 0.013 ether, "bob should end with 0.013 xpufETH");

        assertTrue(l2RewardManager.isClaimed(startEpoch, endEpoch, alice));
        assertTrue(l2RewardManager.isClaimed(startEpoch, endEpoch, bob));
        assertTrue(l2RewardManager.isClaimed(startEpoch, endEpoch, charlie));
    }

    function test_claimRewardsDifferentExchangeRate() public {
        // The ethToPufETHRate is changed to 0.9 ether, so alice's reward should be 0.01308 * 0.9 = 0.011772
        // bob's reward should be 0.013 * 0.9 = 0.0117
        // charlie's reward should be 1 * 0.9 = 0.9

        uint256 aliceAmountToClaim = 0.011772 ether;

        // Build a merkle proof for that
        MerkleProofData[] memory merkleProofDatas = new MerkleProofData[](3);
        merkleProofDatas[0] =
            MerkleProofData({ account: alice, startEpoch: startEpoch, endEpoch: endEpoch, amount: 0.01308 ether });
        merkleProofDatas[1] =
            MerkleProofData({ account: bob, startEpoch: startEpoch, endEpoch: endEpoch, amount: 0.013 ether });
        merkleProofDatas[2] =
            MerkleProofData({ account: charlie, startEpoch: startEpoch, endEpoch: endEpoch, amount: 1 ether });

        // total reward amount calculated for merkle tree
        rewardsAmount = 0.01308 ether + 0.013 ether + 1 ether;

        deal(address(xPufETHProxy), address(l2RewardManager), rewardsAmount);

        // the exchange rate is changed to 1ether -> 0.9 ether
        ethToPufETHRate = 0.9 ether;
        rewardsRoot = _buildMerkleProof(merkleProofDatas);

        // Post the rewards root
        L1RewardManagerStorage.MintAndBridgeData memory bridgingCalldata = L1RewardManagerStorage.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IL1RewardManager.BridgingParams memory bridgingParams = IL1RewardManager.BridgingParams({
            bridgingType: IL1RewardManager.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        // total xPufETH amount to be minted and bridged
        // this amount is calculated based on the exchange rate
        amountAdjustedForExchangeRate = (rewardsAmount * ethToPufETHRate) / 1 ether;

        vm.startPrank(address(l1RewardManager));
        deal(address(xPufETHProxy), address(l1RewardManager), rewardsAmount);
        xPufETHProxy.approve(address(mockBridge), rewardsAmount);

        vm.expectEmit();
        emit IL2RewardManager.RewardRootAndRatePosted(rewardsAmount, ethToPufETHRate, startEpoch, endEpoch, rewardsRoot);
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETHProxy),
            address(this),
            amountAdjustedForExchangeRate,
            uint256(0),
            encodedCallData
        );

        vm.warp(block.timestamp + 5 days);

        // Claim the rewards
        // Alice amount
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.01308 ether;

        bytes32[][] memory aliceProofs = new bytes32[][](1);
        aliceProofs[0] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 0);

        assertEq(xPufETHProxy.balanceOf(alice), 0, "alice should start with zero balance");

        vm.startPrank(alice);

        IL2RewardManager.ClaimOrder[] memory claimOrders = new IL2RewardManager.ClaimOrder[](1);
        claimOrders[0] = IL2RewardManager.ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: alice,
            amount: amounts[0],
            merkleProof: aliceProofs[0]
        });

        vm.expectEmit();
        emit IL2RewardManager.Claimed(alice, alice, startEpoch, endEpoch, aliceAmountToClaim);
        l2RewardManager.claimRewards(claimOrders);
        assertEq(xPufETHProxy.balanceOf(alice), aliceAmountToClaim, "alice should end with 0.011772 xpufETH");

        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.AlreadyClaimed.selector, startEpoch, endEpoch, alice));
        l2RewardManager.claimRewards(claimOrders);
    }

    function testFuzz_rewardsClaiming(
        uint256 ethToPufETH,
        uint256 aliceAmount,
        uint256 bobAmount,
        uint256 charlieAmount
    ) public {
        ethToPufETH = bound(ethToPufETH, 0.98 ether, 0.999 ether);

        // Randomize the rewards amount
        aliceAmount = bound(aliceAmount, 0, 3 ether);
        bobAmount = bound(bobAmount, 0, 0.1 ether);
        charlieAmount = bound(charlieAmount, 0, 5 ether);

        // Build merkle proof data
        MerkleProofData[] memory merkleProofDatas = new MerkleProofData[](3);
        merkleProofDatas[0] =
            MerkleProofData({ account: alice, startEpoch: startEpoch, endEpoch: endEpoch, amount: aliceAmount });
        merkleProofDatas[1] =
            MerkleProofData({ account: bob, startEpoch: startEpoch, endEpoch: endEpoch, amount: bobAmount });
        merkleProofDatas[2] =
            MerkleProofData({ account: charlie, startEpoch: startEpoch, endEpoch: endEpoch, amount: charlieAmount });

        // total reward amount calculated for merkle tree
        rewardsAmount = aliceAmount + bobAmount + charlieAmount;
        rewardsRoot = _buildMerkleProof(merkleProofDatas);

        L1RewardManagerStorage.MintAndBridgeData memory bridgingCalldata = L1RewardManagerStorage.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETH,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IL1RewardManager.BridgingParams memory bridgingParams = IL1RewardManager.BridgingParams({
            bridgingType: IL1RewardManager.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        // Lockbox is address(0), we are siimulating minting on L2 this way
        vm.startPrank(address(xERC20Lockbox));
        xPufETHProxy.mint(address(l2RewardManager), ((rewardsAmount * ethToPufETH) / 1 ether));

        vm.startPrank(address(mockBridge));
        l2RewardManager.xReceive(
            bytes32(0),
            ((rewardsAmount * ethToPufETH) / 1 ether),
            address(xPufETHProxy),
            address(l1RewardManager),
            0,
            encodedCallData
        );

        vm.warp(block.timestamp + 5 days);

        bytes32[][] memory merkleProofs = new bytes32[][](3);
        merkleProofs[0] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 0);
        merkleProofs[1] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 1);
        merkleProofs[2] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 2);

        IL2RewardManager.ClaimOrder[] memory claimOrders = new IL2RewardManager.ClaimOrder[](3);
        claimOrders[0] = IL2RewardManager.ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: alice,
            amount: aliceAmount,
            merkleProof: merkleProofs[0]
        });
        claimOrders[1] = IL2RewardManager.ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: bob,
            amount: bobAmount,
            merkleProof: merkleProofs[1]
        });
        claimOrders[2] = IL2RewardManager.ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: charlie,
            amount: charlieAmount,
            merkleProof: merkleProofs[2]
        });

        l2RewardManager.claimRewards(claimOrders);

        // The reward manager might have some dust left
        // 2 wei rounding allowed
        assertApproxEqAbs(
            xPufETHProxy.balanceOf(address(l2RewardManager)), 0, 2, "l2rewardManager should end with zero balance"
        );

        // We need to upscale by *1 ether, because if the aliceBalance is very small, it rounds to 0
        assertApproxEqAbs((xPufETHProxy.balanceOf(alice) * 1 ether / ethToPufETH), aliceAmount, 2, "Alice ETH amount");
        assertApproxEqAbs((xPufETHProxy.balanceOf(bob) * 1 ether / ethToPufETH), bobAmount, 2, "Bob ETH amount");
        assertApproxEqAbs(
            (xPufETHProxy.balanceOf(charlie) * 1 ether / ethToPufETH), charlieAmount, 2, "Charlie ETH amount"
        );
    }

    function _buildMerkleProof(MerkleProofData[] memory merkleProofDatas) internal returns (bytes32 root) {
        rewardsMerkleProof = new Merkle();

        rewardsMerkleProofData = new bytes32[](merkleProofDatas.length);

        for (uint256 i = 0; i < merkleProofDatas.length; ++i) {
            MerkleProofData memory merkleProofData = merkleProofDatas[i];
            rewardsMerkleProofData[i] = keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(
                            merkleProofData.account,
                            merkleProofData.startEpoch,
                            merkleProofData.endEpoch,
                            merkleProofData.amount
                        )
                    )
                )
            );
        }

        root = rewardsMerkleProof.getRoot(rewardsMerkleProofData);
    }
}
