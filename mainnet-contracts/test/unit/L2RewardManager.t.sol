// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import {UnitTestHelper} from "../helpers/UnitTestHelper.sol";
import {L2RewardManager} from "../../src/l2-contracts/L2RewardManager.sol";
import {IL2RewardManager} from "../../src/interface/IL2RewardManager.sol";
import {BridgingParams, BridgingType, MintAndBridgeParams, ClaimOrder} from "../../src/struct/L2RewardManagerInfo.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockBridge} from "../mocks/BridgeMock.sol";
import {Merkle} from "murky/Merkle.sol";

contract L2RewardManagerTest is UnitTestHelper {
    L2RewardManager public l2RewardManager;
    ERC20Mock public xPufETH;
    MockBridge public mockBridge;

    Merkle rewardsMerkleProof;
    bytes32[] rewardsMerkleProofData;

    address l1_vault = address(0x1);

    function setUp() public override {
        super.setUp();
        // Deploy the MockBridge contract
        mockBridge = new MockBridge();
        // Deploy the MockERC20 token
        xPufETH = new ERC20Mock("xPufETH", "xPufETH");
        address l2RewardManagerImp = address(
            new L2RewardManager(address(xPufETH), l1_vault)
        );
        l2RewardManager = L2RewardManager(
            address(
                new ERC1967Proxy(
                    l2RewardManagerImp,
                    abi.encodeCall(
                        L2RewardManager.initialize,
                        (address(accessManager))
                    )
                )
            )
        );

        // Deal some tokens to the contract and test accounts
        deal(address(xPufETH), address(this), 1000 ether);
        deal(address(xPufETH), address(l2RewardManager), 1000 ether);
    }

    function test_MintAndBridgeRewardsSuccess() public {
        uint64 startEpoch = 1;
        uint64 endEpoch = 2;
        uint128 rewardsAmount = 100 ether;
        uint128 ethToPufETHRate = 1 ether;
        bytes32 rewardsRoot = keccak256(abi.encodePacked("testRoot"));

        MintAndBridgeParams memory bridgingCalldata = MintAndBridgeParams({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        BridgingParams memory bridgingParams = BridgingParams({
            bridgingType: BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(l1_vault);

        vm.expectEmit();
        emit IL2RewardManager.RewardRootAndRatePosted(
            rewardsAmount,
            ethToPufETHRate,
            startEpoch,
            endEpoch,
            rewardsRoot
        );
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        bytes32 result = mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETH),
            address(this),
            rewardsAmount,
            uint256(0),
            encodedCallData
        );
        console.log("rewardAmount", rewardsAmount);
        console.logBytes32(result);
        console.logBytes32(keccak256(abi.encodePacked(rewardsAmount)));

        assertEq(result, keccak256(abi.encodePacked(rewardsAmount)));
    }

    function testRevert_MintAndBridgeRewardsInvalidAmount() public {
        uint64 startEpoch = 1;
        uint64 endEpoch = 2;
        uint128 rewardsAmount = 100 ether;
        uint128 ethToPufETHRate = 1 ether;
        bytes32 rewardsRoot = keccak256(abi.encodePacked("testRoot"));

        MintAndBridgeParams memory bridgingCalldata = MintAndBridgeParams({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        BridgingParams memory bridgingParams = BridgingParams({
            bridgingType: BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(l1_vault);

        vm.expectRevert(
            abi.encodeWithSelector(IL2RewardManager.InvalidAmount.selector)
        );
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        bytes32 result = mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETH),
            address(this),
            0 ether, // invalid amount transfered
            uint256(0),
            encodedCallData
        );
    }

    function testRevert_MintAndBridgeRewardsInvalidAsset() public {
        uint64 startEpoch = 1;
        uint64 endEpoch = 2;
        uint128 rewardsAmount = 100 ether;
        uint128 ethToPufETHRate = 1 ether;
        bytes32 rewardsRoot = keccak256(abi.encodePacked("testRoot"));

        MintAndBridgeParams memory bridgingCalldata = MintAndBridgeParams({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        BridgingParams memory bridgingParams = BridgingParams({
            bridgingType: BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(l1_vault);

        vm.expectRevert(
            abi.encodeWithSelector(IL2RewardManager.InvalidAsset.selector)
        );
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        bytes32 result = mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(0x2), // invalid asset transfered
            address(this),
            rewardsAmount,
            uint256(0),
            encodedCallData
        );
    }

    struct MerkleProofData {
        address account;
        uint64 startEpoch;
        uint64 endEpoch;
        uint128 amount;
    }

    function test_claimRewardsAllCases() public {
        // 3 validators got the rewards
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address charlie = makeAddr("charlie");
        uint64 startEpoch = 1;
        uint64 endEpoch = 2;

        // Build a merkle proof for that
        MerkleProofData[] memory validatorRewards = new MerkleProofData[](3);
        validatorRewards[0] = MerkleProofData({
            account: alice,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            amount: 0.01308 ether
        });
        validatorRewards[1] = MerkleProofData({
            account: bob,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            amount: 0.013 ether
        });
        validatorRewards[2] = MerkleProofData({
            account: charlie,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            amount: 1 ether
        });

        uint128 rewardsAmount = 0.01308 ether + 0.013 ether + 1 ether;

        // vm.deal(l2RewardManager, rewardsAmount);

        uint128 ethToPufETHRate = 1 ether;
        bytes32 rewardsRoot = _buildMerkleProof(validatorRewards);

        // Post the rewards root
        MintAndBridgeParams memory bridgingCalldata = MintAndBridgeParams({
            rewardsAmount: rewardsAmount,
            ethToPufETHRate: ethToPufETHRate,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: rewardsRoot,
            rewardsURI: "uri"
        });

        BridgingParams memory bridgingParams = BridgingParams({
            bridgingType: BridgingType.MintAndBridge,
            data: abi.encode(bridgingCalldata)
        });
        bytes memory encodedCallData = abi.encode(bridgingParams);

        vm.startPrank(l1_vault);

        vm.expectEmit();
        emit IL2RewardManager.RewardRootAndRatePosted(
            rewardsAmount,
            ethToPufETHRate,
            startEpoch,
            endEpoch,
            rewardsRoot
        );
        // calling xcall on L1 which triggers xReceive on L2 using mockBridge here
        bytes32 result = mockBridge.xcall(
            uint32(0),
            address(l2RewardManager),
            address(xPufETH),
            address(this),
            rewardsAmount,
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
        emit IL2RewardManager.Claimed(alice, startEpoch, endEpoch, amounts[0]);
        l2RewardManager.claimRewards(claimOrders);
        assertEq(
            xPufETH.balanceOf(alice),
            0.01308 ether,
            "alice should end with 0.01308 xpufETH"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IL2RewardManager.AlreadyClaimed.selector,
                startEpoch,
                endEpoch,
                alice
            )
        );
        l2RewardManager.claimRewards(claimOrders);

        // Bob amount
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IL2RewardManager.AlreadyClaimed.selector,
                startEpoch,
                endEpoch,
                alice
            )
        );
        l2RewardManager.claimRewards(claimOrders);

        bytes32[][] memory bobProofs = new bytes32[][](1);
        bobProofs[0] = rewardsMerkleProof.getProof(rewardsMerkleProofData, 1);
        bytes32[][] memory charlieProofs = new bytes32[][](1);
        charlieProofs[0] = rewardsMerkleProof.getProof(
            rewardsMerkleProofData,
            2
        );

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
        vm.expectRevert(
            abi.encodeWithSelector(IL2RewardManager.InvalidProof.selector)
        );
        l2RewardManager.claimRewards(claimOrders);

        assertEq(
            xPufETH.balanceOf(charlie),
            0,
            "charlie should start with zero balance"
        );
        // Bob claiming for charlie (bob is msg.sender)
        claimOrders[0] = ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: charlie,
            amount: amounts[0],
            merkleProof: charlieProofs[0]
        });
        l2RewardManager.claimRewards(claimOrders);
        assertEq(
            xPufETH.balanceOf(charlie),
            1 ether,
            "charlie should end with 1 xpufETH"
        );

        // Mutate amounts, set back Bob's amount
        amounts[0] = 0.013 ether;
        assertEq(
            xPufETH.balanceOf(bob),
            0,
            "bob should start with zero balance"
        );
        // Bob claiming with his proof
        claimOrders[0] = ClaimOrder({
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            account: bob,
            amount: amounts[0],
            merkleProof: bobProofs[0]
        });
        l2RewardManager.claimRewards(claimOrders);
        assertEq(
            xPufETH.balanceOf(bob),
            0.013 ether,
            "bob should end with 0.013 xpufETH"
        );

        // assertEq(xPufETH.balanceOf(account), amount);
        // assertTrue(l2RewardManager.isClaimed(startEpoch, endEpoch, account));
    }

    function _buildMerkleProof(
        MerkleProofData[] memory validatorRewards
    ) internal returns (bytes32 root) {
        rewardsMerkleProof = new Merkle();

        rewardsMerkleProofData = new bytes32[](validatorRewards.length);

        for (uint256 i = 0; i < validatorRewards.length; ++i) {
            MerkleProofData memory validatorData = validatorRewards[i];
            rewardsMerkleProofData[i] = keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(
                            validatorData.account,
                            validatorData.startEpoch,
                            validatorData.endEpoch,
                            validatorData.amount
                        )
                    )
                )
            );
        }

        root = rewardsMerkleProof.getRoot(rewardsMerkleProofData);
    }
}
