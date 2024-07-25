// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { L2RewardManager } from "../../src/L2RewardManager.sol";
import { IL2RewardManager } from "../../src/interface/IL2RewardManager.sol";
import { IPufferVaultV3 } from "mainnet-contracts/src/interface/IPufferVaultV3.sol";
import { ERC20Mock } from "mainnet-contracts/test/mocks/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BridgeMock } from "../mocks/BridgeMock.sol";
import { Merkle } from "murky/Merkle.sol";
import { ROLE_ID_BRIDGE } from "mainnet-contracts/script/Roles.sol";
import { ClaimOrder, EpochRecord } from "../../src/struct/L2RewardManagerInfo.sol";

/**
 * forge test --match-path test/unit/L2RewardManager.t.sol -vvvv
 */
contract L2RewardManagerTest is Test {
    L2RewardManager public l2RewardManager;
    ERC20Mock public xPufETH;
    BridgeMock public mockBridge;

    Merkle rewardsMerkleProof;
    bytes32[] rewardsMerkleProofData;

    address l1_vault = address(0x1);

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

    function setUp() public {
        accessManager = new AccessManager(address(this));

        // Deploy the BridgeMock contract
        mockBridge = new BridgeMock();
        // Deploy the MockERC20 token
        xPufETH = new ERC20Mock("xPufETH", "xPufETH");
        address l2RewardManagerImp = address(new L2RewardManager(address(xPufETH), l1_vault));
        l2RewardManager = L2RewardManager(
            address(
                new ERC1967Proxy(
                    l2RewardManagerImp, abi.encodeCall(L2RewardManager.initialize, (address(accessManager)))
                )
            )
        );
        bytes[] memory calldatas = new bytes[](2);
        bytes4[] memory bridgeSelectors = new bytes4[](1);
        bridgeSelectors[0] = IL2RewardManager.xReceive.selector;
        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, address(l2RewardManager), bridgeSelectors, ROLE_ID_BRIDGE
        );
        calldatas[1] = abi.encodeWithSelector(AccessManager.grantRole.selector, ROLE_ID_BRIDGE, address(mockBridge), 0);

        accessManager.multicall(calldatas);

        // Deal some tokens to the contract and test accounts
        deal(address(xPufETH), address(this), 1000 ether);
        deal(address(xPufETH), address(l2RewardManager), 1000 ether);
    }

    function test_MintAndBridgeRewardsSuccess() public {
        rewardsAmount = 100 ether;
        ethToPufETHRate = 1 ether;
        rewardsRoot = keccak256(abi.encodePacked("testRoot"));

        IPufferVaultV3.MintAndBridgeData memory bridgingCalldata = IPufferVaultV3.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IPufferVaultV3.BridgingParams memory bridgingParams = IPufferVaultV3.BridgingParams({
            bridgingType: IPufferVaultV3.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(l1_vault);

        vm.expectEmit();
        emit IL2RewardManager.RewardRootAndRatePosted(rewardsAmount, ethToPufETHRate, startEpoch, endEpoch, rewardsRoot);
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETH),
            address(this),
            rewardsAmount,
            uint256(0),
            encodedCallData
        );

        EpochRecord memory epochRecord = l2RewardManager.getEpochRecord(startEpoch, endEpoch);
        assertEq(epochRecord.ethToPufETHRate, ethToPufETHRate, "ethToPufETHRate should be stored in storage correctly");
        assertEq(epochRecord.rewardRoot, rewardsRoot, "rewardsRoot should be stored in storage correctly");
    }

    function testRevert_MintAndBridgeRewardsInvalidAmount() public {
        rewardsAmount = 100 ether;
        ethToPufETHRate = 1 ether;
        rewardsRoot = keccak256(abi.encodePacked("testRoot"));

        IPufferVaultV3.MintAndBridgeData memory bridgingCalldata = IPufferVaultV3.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IPufferVaultV3.BridgingParams memory bridgingParams = IPufferVaultV3.BridgingParams({
            bridgingType: IPufferVaultV3.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(l1_vault);

        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.InvalidAmount.selector));
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETH),
            address(this),
            0 ether, // invalid amount transfered
            uint256(0),
            encodedCallData
        );
    }

    struct MerkleProofData {
        address account;
        uint256 startEpoch;
        uint256 endEpoch;
        uint256 amount;
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

        // vm.deal(l2RewardManager, rewardsAmount);

        ethToPufETHRate = 1 ether;
        rewardsRoot = _buildMerkleProof(merkleProofDatas);

        // Post the rewards root
        IPufferVaultV3.MintAndBridgeData memory bridgingCalldata = IPufferVaultV3.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IPufferVaultV3.BridgingParams memory bridgingParams = IPufferVaultV3.BridgingParams({
            bridgingType: IPufferVaultV3.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(l1_vault);

        vm.expectEmit();
        emit IL2RewardManager.RewardRootAndRatePosted(rewardsAmount, ethToPufETHRate, startEpoch, endEpoch, rewardsRoot);
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETH),
            address(this),
            rewardsAmount,
            uint256(0),
            encodedCallData
        );

        EpochRecord memory epochRecord = l2RewardManager.getEpochRecord(startEpoch, endEpoch);
        assertEq(epochRecord.ethToPufETHRate, ethToPufETHRate, "ethToPufETHRate should be stored in storage correctly");
        assertEq(epochRecord.rewardRoot, rewardsRoot, "rewardsRoot should be stored in storage correctly");

        // Claim the rewards
        // Alice amount
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.01308 ether;

        bytes32[][] memory aliceProofs = new bytes32[][](1);
        aliceProofs[0] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 0);

        assertEq(alice.balance, 0, "alice should start with zero balance");

        vm.startPrank(alice);

        ClaimOrder[] memory claimOrders = new ClaimOrder[](1);
        claimOrders[0] = ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: alice,
            amount: amounts[0],
            merkleProof: aliceProofs[0]
        });

        vm.expectEmit();
        emit IL2RewardManager.Claimed(alice, alice, startEpoch, endEpoch, amounts[0]);
        l2RewardManager.claimRewards(claimOrders);
        assertEq(xPufETH.balanceOf(alice), 0.01308 ether, "alice should end with 0.01308 xpufETH");

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

        claimOrders[0] = ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: bob,
            amount: amounts[0],
            merkleProof: charlieProofs[0]
        });
        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.InvalidProof.selector));
        l2RewardManager.claimRewards(claimOrders);

        assertEq(xPufETH.balanceOf(charlie), 0, "charlie should start with zero balance");
        // Bob claiming for charlie (bob is msg.sender)
        claimOrders[0] = ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: charlie,
            amount: amounts[0],
            merkleProof: charlieProofs[0]
        });
        l2RewardManager.claimRewards(claimOrders);
        assertEq(xPufETH.balanceOf(charlie), 1 ether, "charlie should end with 1 xpufETH");

        // Mutate amounts, set back Bob's amount
        amounts[0] = 0.013 ether;
        assertEq(xPufETH.balanceOf(bob), 0, "bob should start with zero balance");
        // Bob claiming with his proof
        claimOrders[0] = ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: bob,
            amount: amounts[0],
            merkleProof: bobProofs[0]
        });
        l2RewardManager.claimRewards(claimOrders);
        assertEq(xPufETH.balanceOf(bob), 0.013 ether, "bob should end with 0.013 xpufETH");

        assertTrue(l2RewardManager.isClaimed(startEpoch, endEpoch, alice));
        assertTrue(l2RewardManager.isClaimed(startEpoch, endEpoch, bob));
        assertTrue(l2RewardManager.isClaimed(startEpoch, endEpoch, charlie));
    }

    function test_claimRewardsDifferentExchangeRate() public {
        // The ethToPufETHRate is changed to 0.9 ether, so alice's reward should be 0.01308 * 0.9 = 0.011772
        // bob's reward should be 0.013 * 0.9 = 0.0117
        // charlie's reward should be 1 * 0.9 = 0.9

        uint256 aliceAmountToClaim = 0.011772 ether;
        uint256 bobAmountToClaim = 0.0117 ether;
        uint256 charlieAmountToClaim = 0.9 ether;

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

        // the exchange rate is changed to 1ether-> 0.9 ether
        ethToPufETHRate = 0.9 ether;
        rewardsRoot = _buildMerkleProof(merkleProofDatas);

        // Post the rewards root
        IPufferVaultV3.MintAndBridgeData memory bridgingCalldata = IPufferVaultV3.MintAndBridgeData({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        IPufferVaultV3.BridgingParams memory bridgingParams = IPufferVaultV3.BridgingParams({
            bridgingType: IPufferVaultV3.BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        // total xPufETH amount to be minted and bridged
        // this amount is calculated based on the exchange rate
        amountAdjustedForExchangeRate = rewardsAmount * ethToPufETHRate / 1 ether;

        vm.startPrank(l1_vault);

        vm.expectEmit();
        emit IL2RewardManager.RewardRootAndRatePosted(rewardsAmount, ethToPufETHRate, startEpoch, endEpoch, rewardsRoot);
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETH),
            address(this),
            amountAdjustedForExchangeRate,
            uint256(0),
            encodedCallData
        );

        // Claim the rewards
        // Alice amount
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.01308 ether;

        bytes32[][] memory aliceProofs = new bytes32[][](1);
        aliceProofs[0] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 0);

        assertEq(alice.balance, 0, "alice should start with zero balance");

        vm.startPrank(alice);

        ClaimOrder[] memory claimOrders = new ClaimOrder[](1);
        claimOrders[0] = ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: alice,
            amount: amounts[0],
            merkleProof: aliceProofs[0]
        });

        vm.expectEmit();
        emit IL2RewardManager.Claimed(alice, alice, startEpoch, endEpoch, aliceAmountToClaim);
        l2RewardManager.claimRewards(claimOrders);
        assertEq(xPufETH.balanceOf(alice), aliceAmountToClaim, "alice should end with 0.011772 xpufETH");

        vm.expectRevert(abi.encodeWithSelector(IL2RewardManager.AlreadyClaimed.selector, startEpoch, endEpoch, alice));
        l2RewardManager.claimRewards(claimOrders);
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
