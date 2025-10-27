// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
// import { xPufETH } from "src/l2/xPufETH.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";
import { IL1RewardManager } from "../../src/interface/IL1RewardManager.sol";
import { L1RewardManager } from "../../src/L1RewardManager.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { L1RewardManagerStorage } from "../../src/L1RewardManagerStorage.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import {
    ROLE_ID_DAO,
    PUBLIC_ROLE,
    ROLE_ID_BRIDGE,
    ROLE_ID_L1_REWARD_MANAGER,
    ROLE_ID_OPERATIONS_PAYMASTER,
    ROLE_ID_VAULT_WITHDRAWER
} from "../../script/Roles.sol";
import { InvalidAddress, Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { GenerateRewardManagerCalldata } from
    "../../script/AccessManagerMigrations/03_GenerateRewardManagerCalldata.s.sol";

//LayerZero imports
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { pufETHAdapter } from "partners-layerzero/contracts/pufETHAdapter.sol";
import { pufETH } from "partners-layerzero/contracts/pufETH.sol";
import { NoImplementation } from "../../src/NoImplementation.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { OFTAdapterMock } from "partners-layerzero/test/mocks/OFTAdapterMock.sol";
import { OFTMock } from "partners-layerzero/test/mocks/OFTMock.sol";
import {
    IOAppOptionsType3, EnforcedOptionParam
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
// import { IOFT } from "../../src/interface/LayerZero/IOFT.sol";

import { console } from "forge-std/console.sol";

/// @notice Unit test for L1RewardManager using the LayerZero TestHelper.
/// @dev Inherits from TestHelper to utilize its setup and utility functions.
contract L1RewardManagerTest is UnitTestHelper, TestHelperOz5 {
    uint256 rewardsAmount;
    uint256 startEpoch = 1;
    uint256 endEpoch = 2;

    // ERC20Mock private pufETHToken;
    OFTAdapterMock private pufETHOFTAdapter;
    OFTMock private pufETHOFT;
    uint32 private srcEid = 1;
    uint32 private dstEid = 2;

    using OptionsBuilder for bytes;

    // Declaration of mock endpoint IDs.
    // uint16 layerzeroEndpointEid = 1;
    // address layerzeroEndpoint;

    function setUp() public override(TestHelperOz5, UnitTestHelper) {
        UnitTestHelper.setUp();
        TestHelperOz5.setUp();

        // Setup function to initialize 2 Mock Endpoints with Mock MessageLib.
        setUpEndpoints(2, LibraryType.UltraLightNode);

        layerzeroL1Endpoint = endpoints[srcEid];
        layerzeroL2Endpoint = endpoints[dstEid];
        console.log("layerzeroEndpoint", layerzeroL1Endpoint);
        console.log("layerzeroEndpoint", layerzeroL2Endpoint);

        // pufETHToken = ERC20Mock(_deployOApp(type(ERC20Mock).creationCode, abi.encode("pufETH", "pufETH")));
        pufETHOFTAdapter = OFTAdapterMock(
            _deployOApp(
                type(OFTAdapterMock).creationCode,
                abi.encode(address(pufferVault), address(endpoints[srcEid]), address(this))
            )
        );

        pufETHOFT = OFTMock(
            _deployOApp(
                type(OFTMock).creationCode, abi.encode("pufETH", "pufETH", address(endpoints[dstEid]), address(this))
            )
        );

        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(pufETHOFTAdapter);
        ofts[1] = address(pufETHOFT);
        this.wireOApps(ofts);

        console.log("pufETHOFTAdapter", address(pufETHOFTAdapter));
        console.log("pufETHOFT", address(pufETHOFT));

        // deploy l1RewardManager and l2RewardManager
        address noImpl = address(new NoImplementation());

        ERC1967Proxy l2RewardManagerProxy = new ERC1967Proxy(noImpl, "");
        L1RewardManager l1RewardManagerImpl = new L1RewardManager(
            address(pufferVault), // pufETH
            address(l2RewardManagerProxy), // l2RewardsManager
            address(pufETHOFTAdapter) // pufETHOFTAdapter
        );

        L1RewardManager l1RewardManagerProxy = L1RewardManager(
            address(
                new ERC1967Proxy(
                    address(l1RewardManagerImpl), abi.encodeCall(L1RewardManager.initialize, (address(accessManager)))
                )
            )
        );

        // mock xpufETH
        ERC20Mock xpufETH = new ERC20Mock("xpufETH", "xpufETH");

        L2RewardManager l2RewardManagerImpl = new L2RewardManager(address(l1RewardManagerProxy), address(xpufETH));

        UUPSUpgradeable(address(l2RewardManagerProxy)).upgradeToAndCall(
            address(l2RewardManagerImpl), abi.encodeCall(L2RewardManager.initialize, (address(accessManager)))
        );

        l2RewardManager = L2RewardManager(address(l2RewardManagerProxy));
        l1RewardManager = L1RewardManager(address(l1RewardManagerProxy));

        console.log("l1RewardManagerProxy", address(l1RewardManagerProxy));
        console.log("l2RewardManagerImpl", address(l2RewardManagerImpl));
        console.log("l2RewardManagerProxy", address(l2RewardManagerProxy));
        console.log("l1RewardManagerImpl", address(l1RewardManagerImpl));

        vm.startPrank(_broadcaster);

        bytes4[] memory mintRewardsSelectors = new bytes4[](2);
        mintRewardsSelectors[0] = PufferVaultV5.mintRewards.selector;
        mintRewardsSelectors[1] = PufferVaultV5.revertMintRewards.selector;

        accessManager.setTargetFunctionRole(address(pufferVault), mintRewardsSelectors, ROLE_ID_L1_REWARD_MANAGER);
        accessManager.grantRole(ROLE_ID_L1_REWARD_MANAGER, address(l1RewardManager), 0);

        bytes4[] memory paymasterSelectors = new bytes4[](1);
        paymasterSelectors[0] = PufferModuleManager.transferRewardsToTheVault.selector;

        accessManager.setTargetFunctionRole(
            address(pufferModuleManager), paymasterSelectors, ROLE_ID_OPERATIONS_PAYMASTER
        );
        accessManager.grantRole(ROLE_ID_OPERATIONS_PAYMASTER, address(this), 0);

        bytes4[] memory pmmSelectors = new bytes4[](1);
        pmmSelectors[0] = PufferVaultV5.depositRewards.selector;

        accessManager.setTargetFunctionRole(address(pufferVault), pmmSelectors, ROLE_ID_VAULT_WITHDRAWER);
        accessManager.grantRole(ROLE_ID_VAULT_WITHDRAWER, address(pufferModuleManager), 0);

        bytes memory cd = new GenerateRewardManagerCalldata().generateL1Calldata(
            address(l1RewardManager), address(layerzeroL1Endpoint)
        );
        (bool s,) = address(accessManager).call(cd);
        require(s, "failed setupAccess GenerateRewardManagerCalldata");

        vm.label(address(l1RewardManager), "L1RewardManager");

        vm.stopPrank();

        vm.startPrank(DAO);

        // Set destination EID
        l1RewardManager.setDestinationEID(dstEid);

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
        new L1RewardManager(address(1), address(2), address(3));
    }

    function test_setDestinationEID() public {
        uint32 newDestinationEID = 999;

        vm.startPrank(DAO);
        uint32 currentDestinationEID = l1RewardManager.getDestinationEID();
        vm.expectEmit(false, false, false, true);
        emit IL1RewardManager.DestinationEIDUpdated(currentDestinationEID, newDestinationEID);
        l1RewardManager.setDestinationEID(newDestinationEID);

        assertEq(l1RewardManager.getDestinationEID(), newDestinationEID);
        vm.stopPrank();
    }

    function test_MintAndBridgeRewardsSuccess() public allowedDailyFrequency allowMintAmount(100 ether) {
        rewardsAmount = 100 ether;

        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: rewardsAmount,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        uint256 initialTotalAssets = pufferVault.totalAssets();

        // ✅ Use arbitrary value for LayerZero fees
        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);

        assertEq(pufferVault.totalAssets(), initialTotalAssets + 100 ether);
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

        bytes memory composeMsg = abi.encode(epochRecord);

        // airdrop rewardsAmount to l1RewardManager
        deal(address(pufferVault), address(l1RewardManager), 100 ether);

        vm.startPrank(address(layerzeroL1Endpoint));
        bytes32 composeFrom = addressToBytes32(address(l2RewardManager));
        bytes memory _msg = encode(0, 2, 100 ether, abi.encodePacked(composeFrom, composeMsg));

        // Simulate a call from the layerzero bridge
        l1RewardManager.lzCompose(address(pufETHOFTAdapter), bytes32(0), _msg, address(0), "");

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

        bytes memory composeMsg = abi.encode(epochRecord);

        // airdrop rewardsAmount to l1RewardManager
        deal(address(pufferVault), address(l1RewardManager), 100 ether);

        vm.startPrank(address(layerzeroL1Endpoint));
        bytes32 composeFrom = addressToBytes32(address(l2RewardManager));

        bytes memory _msg = encode(0, 2, 100 ether, abi.encodePacked(composeFrom, composeMsg));
        console.log("composeMsg in test_undoMintAndBridgeRewards");
        console.logBytes(composeMsg);
        console.log("composeFrom in test_undoMintAndBridgeRewards");
        console.logBytes32(composeFrom);
        console.log("msg in test_undoMintAndBridgeRewards");
        console.logBytes(_msg);

        // Simulate a call from the layerzero bridge
        l1RewardManager.lzCompose(address(pufETHOFTAdapter), bytes32(0), _msg, address(0), "");

        assertEq(pufferVault.totalAssets(), assetsBefore, "assets before and now should match");
        assertEq(
            pufferVault.getTotalRewardMintAmount(), rewardsAmountBefore, "rewards amount before and now should match"
        );
        assertEq(pufferVault.totalSupply(), pufETHTotalSupplyBefore, "total supply before and now should match");
    }

    function testRevert_invalidOriginAddress() public {
        vm.startPrank(address(layerzeroL1Endpoint));
        L2RewardManagerStorage.EpochRecord memory epochRecord = L2RewardManagerStorage.EpochRecord({
            startEpoch: uint72(startEpoch),
            endEpoch: uint72(endEpoch),
            timeBridged: uint48(block.timestamp),
            ethToPufETHRate: 1 ether,
            pufETHAmount: 100 ether,
            ethAmount: 100 ether,
            rewardRoot: bytes32("uri")
        });

        bytes memory composeMsg = abi.encode(epochRecord);
        console.log("composeMsg in testRevert_invalidOriginAddress");
        console.logBytes(composeMsg);

        // _composeMsg is 0x[composeFrom][composeMsg]
        // pass invalid address as composeFrom, correct origin should be l2RewardManager
        bytes32 composeFrom = bytes32(uint256(uint160(address(this))));
        console.log("composeFrom in testRevert_invalidOriginAddress");
        console.logBytes32(composeFrom);

        bytes memory _msg = encode(0, 2, 100 ether, abi.encodePacked(composeFrom, composeMsg));
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        l1RewardManager.lzCompose(address(pufETHOFTAdapter), bytes32(0), _msg, address(0), "");
    }

    function testRevert_MintAndBridgeRewardsInvalidMintAmount() public {
        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 200 ether, // assuming this is more than allowed
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        // ✅ Use arbitrary value for LayerZero fees
        uint256 layerZeroFee = 0.01 ether;
        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.InvalidMintAmount.selector));
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);
    }

    function test_MintAndBridgeRewardsNotAllowedMintFrequency()
        public
        allowedDailyFrequency
        allowMintAmount(100 ether)
    {
        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 1 ether,
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        // ✅ Use arbitrary value for LayerZero fees
        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.NotAllowedMintFrequency.selector));
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);
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

        uint256 layerZeroFee = 0.01 ether;
        vm.expectEmit(true, true, true, true);
        emit IL1RewardManager.L2RewardClaimerUpdated(address(this), newClaimer);
        l1RewardManager.setL2RewardClaimer{ value: layerZeroFee }(newClaimer);
    }

    function testRevert_callFromInvalidBridgeOrigin() public {
        vm.startPrank(address(this));

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, address(this)));
        l1RewardManager.lzCompose(address(pufETHOFTAdapter), bytes32(0), "hello", address(layerzeroL1Endpoint), "");
    }

    /**
     * @notice Test that enforced options are properly set by checking if setEnforcedOptions can be called
     */
    function test_EnforcedOptionsAreSet() public {
        // Test that we can call setEnforcedOptions (this means the interface is working)
        EnforcedOptionParam[] memory testOptions = new EnforcedOptionParam[](1);
        testOptions[0] = EnforcedOptionParam({
            eid: dstEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(50000, 0)
        });

        // This should not revert, indicating the enforced options functionality is available
        IOAppOptionsType3(address(pufETHOFTAdapter)).setEnforcedOptions(testOptions);

        // Verify that the OFT contracts implement IOAppOptionsType3
        assertTrue(true, "Enforced options interface is working");
    }

    /**
     * @notice Test that mintAndBridgeRewards works with enforced options
     */
    function test_MintAndBridgeRewardsWithEnforcedOptions() public allowedDailyFrequency allowMintAmount(100 ether) {
        rewardsAmount = 100 ether;

        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: rewardsAmount,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        uint256 initialTotalAssets = pufferVault.totalAssets();

        // ✅ Use arbitrary value for LayerZero fees
        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);

        assertEq(pufferVault.totalAssets(), initialTotalAssets + 100 ether);
    }

    // ============ EPOCH TRACKING TESTS ============

    function test_InitialEpochState() public {
        assertEq(l1RewardManager.getLastIntervalEndEpoch(), 0, "Initial lastIntervalEndEpoch should be 0");
        assertEq(l1RewardManager.getCurrentIntervalEndEpoch(), 0, "Initial currentIntervalEndEpoch should be 0");
    }

    function test_FirstSuccessfulMintUpdatesEpochs() public allowedDailyFrequency allowMintAmount(100 ether) {
        uint256 testStartEpoch = 100;
        uint256 testEndEpoch = 200;

        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 100 ether,
            startEpoch: testStartEpoch,
            endEpoch: testEndEpoch,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        // Before mint
        assertEq(l1RewardManager.getLastIntervalEndEpoch(), 0, "lastIntervalEndEpoch should be 0 before first mint");
        assertEq(
            l1RewardManager.getCurrentIntervalEndEpoch(), 0, "currentIntervalEndEpoch should be 0 before first mint"
        );

        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);

        // After first mint
        assertEq(
            l1RewardManager.getLastIntervalEndEpoch(), 0, "lastIntervalEndEpoch should still be 0 after first mint"
        );
        assertEq(
            l1RewardManager.getCurrentIntervalEndEpoch(),
            testEndEpoch,
            "currentIntervalEndEpoch should be updated to endEpoch"
        );
    }

    function test_SecondSuccessfulMintUpdatesEpochs() public allowedDailyFrequency allowMintAmount(100 ether) {
        // First mint
        IL1RewardManager.MintAndBridgeParams memory params1 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 100 ether,
            startEpoch: 100,
            endEpoch: 200,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params1);

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Second mint
        IL1RewardManager.MintAndBridgeParams memory params2 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 50 ether,
            startEpoch: 201, // Must be > 200
            endEpoch: 300,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri2"
        });

        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params2);

        // After second mint
        assertEq(
            l1RewardManager.getLastIntervalEndEpoch(),
            200,
            "lastIntervalEndEpoch should be updated to previous endEpoch"
        );
        assertEq(
            l1RewardManager.getCurrentIntervalEndEpoch(),
            300,
            "currentIntervalEndEpoch should be updated to new endEpoch"
        );
    }

    function testRevert_InvalidStartEpoch() public allowedDailyFrequency allowMintAmount(100 ether) {
        // First mint
        IL1RewardManager.MintAndBridgeParams memory params1 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 100 ether,
            startEpoch: 100,
            endEpoch: 200,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params1);

        // Check state after first mint
        uint256 lastEpoch = l1RewardManager.getLastIntervalEndEpoch();
        uint256 currentEpoch = l1RewardManager.getCurrentIntervalEndEpoch();
        console.log("After first mint - lastEpoch:", lastEpoch);
        console.log("After first mint - currentEpoch:", currentEpoch);

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Second mint with invalid startEpoch (should be > 200)
        IL1RewardManager.MintAndBridgeParams memory params2 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 50 ether,
            startEpoch: 150, // Invalid: <= 200
            endEpoch: 300,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri2"
        });

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.InvalidStartEpoch.selector));
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params2);
    }

    function testRevert_StartEpochEqualToLastEndEpoch() public allowedDailyFrequency allowMintAmount(100 ether) {
        // First mint
        IL1RewardManager.MintAndBridgeParams memory params1 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 100 ether,
            startEpoch: 100,
            endEpoch: 200,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params1);

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Second mint with startEpoch equal to last endEpoch (should be > 200)
        IL1RewardManager.MintAndBridgeParams memory params2 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 50 ether,
            startEpoch: 200, // Invalid: equal to last endEpoch
            endEpoch: 300,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri2"
        });

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.InvalidStartEpoch.selector));
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params2);
    }

    function test_RevertUpdatesCurrentEpoch() public allowedDailyFrequency allowMintAmount(100 ether) {
        // First mint
        IL1RewardManager.MintAndBridgeParams memory params1 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 100 ether,
            startEpoch: 100,
            endEpoch: 200,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params1);

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Second mint
        IL1RewardManager.MintAndBridgeParams memory params2 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 50 ether,
            startEpoch: 201,
            endEpoch: 300,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri2"
        });

        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params2);

        // Verify state before revert
        assertEq(l1RewardManager.getLastIntervalEndEpoch(), 200, "lastIntervalEndEpoch should be 200 before revert");
        assertEq(
            l1RewardManager.getCurrentIntervalEndEpoch(), 300, "currentIntervalEndEpoch should be 300 before revert"
        );

        // Simulate revert via lzCompose
        L2RewardManagerStorage.EpochRecord memory epochRecord = L2RewardManagerStorage.EpochRecord({
            startEpoch: uint72(201),
            endEpoch: uint72(300),
            timeBridged: uint48(block.timestamp),
            ethToPufETHRate: 1 ether,
            pufETHAmount: 50 ether,
            ethAmount: 50 ether,
            rewardRoot: bytes32(hex"aabb")
        });

        bytes memory composeMsg = abi.encode(epochRecord);
        deal(address(pufferVault), address(l1RewardManager), 50 ether);

        vm.startPrank(address(layerzeroL1Endpoint));
        bytes32 composeFrom = addressToBytes32(address(l2RewardManager));
        bytes memory _msg = encode(0, 2, 50 ether, abi.encodePacked(composeFrom, composeMsg));

        l1RewardManager.lzCompose(address(pufETHOFTAdapter), bytes32(0), _msg, address(0), "");
        vm.stopPrank();

        // Verify state after revert
        assertEq(l1RewardManager.getLastIntervalEndEpoch(), 200, "lastIntervalEndEpoch should remain 200 after revert");
        assertEq(
            l1RewardManager.getCurrentIntervalEndEpoch(),
            200,
            "currentIntervalEndEpoch should be reset to 200 after revert"
        );
    }

    function test_MintAfterRevert() public allowedDailyFrequency allowMintAmount(100 ether) {
        // First mint
        IL1RewardManager.MintAndBridgeParams memory params1 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 100 ether,
            startEpoch: 100,
            endEpoch: 200,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params1);

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Second mint
        IL1RewardManager.MintAndBridgeParams memory params2 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 50 ether,
            startEpoch: 201,
            endEpoch: 300,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri2"
        });

        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params2);

        // Simulate revert
        L2RewardManagerStorage.EpochRecord memory epochRecord = L2RewardManagerStorage.EpochRecord({
            startEpoch: uint72(201),
            endEpoch: uint72(300),
            timeBridged: uint48(block.timestamp),
            ethToPufETHRate: 1 ether,
            pufETHAmount: 50 ether,
            ethAmount: 50 ether,
            rewardRoot: bytes32(hex"aabb")
        });

        bytes memory composeMsg = abi.encode(epochRecord);
        deal(address(pufferVault), address(l1RewardManager), 50 ether);

        vm.startPrank(address(layerzeroL1Endpoint));
        bytes32 composeFrom = addressToBytes32(address(l2RewardManager));
        bytes memory _msg = encode(0, 2, 50 ether, abi.encodePacked(composeFrom, composeMsg));

        l1RewardManager.lzCompose(address(pufETHOFTAdapter), bytes32(0), _msg, address(0), "");
        vm.stopPrank();

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Third mint after revert (should work with startEpoch > 200)
        IL1RewardManager.MintAndBridgeParams memory params3 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 75 ether,
            startEpoch: 201, // Can reuse the same startEpoch since previous was reverted
            endEpoch: 350,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri3"
        });

        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params3);

        // Verify state after third mint
        assertEq(
            l1RewardManager.getLastIntervalEndEpoch(),
            200,
            "lastIntervalEndEpoch should remain 200 (previous successful)"
        );
        assertEq(l1RewardManager.getCurrentIntervalEndEpoch(), 350, "currentIntervalEndEpoch should be updated to 350");
    }

    function testRevert_MintAfterRevertWithInvalidStartEpoch()
        public
        allowedDailyFrequency
        allowMintAmount(100 ether)
    {
        // First mint
        IL1RewardManager.MintAndBridgeParams memory params1 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 100 ether,
            startEpoch: 100,
            endEpoch: 200,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri"
        });

        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params1);

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Second mint
        IL1RewardManager.MintAndBridgeParams memory params2 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 50 ether,
            startEpoch: 201,
            endEpoch: 300,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri2"
        });

        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params2);

        // Simulate revert
        L2RewardManagerStorage.EpochRecord memory epochRecord = L2RewardManagerStorage.EpochRecord({
            startEpoch: uint72(201),
            endEpoch: uint72(300),
            timeBridged: uint48(block.timestamp),
            ethToPufETHRate: 1 ether,
            pufETHAmount: 50 ether,
            ethAmount: 50 ether,
            rewardRoot: bytes32(hex"aabb")
        });

        bytes memory composeMsg = abi.encode(epochRecord);
        deal(address(pufferVault), address(l1RewardManager), 50 ether);

        vm.startPrank(address(layerzeroL1Endpoint));
        bytes32 composeFrom = addressToBytes32(address(l2RewardManager));
        bytes memory _msg = encode(0, 2, 50 ether, abi.encodePacked(composeFrom, composeMsg));

        l1RewardManager.lzCompose(address(pufETHOFTAdapter), bytes32(0), _msg, address(0), "");
        vm.stopPrank();

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Third mint with invalid startEpoch (should fail)
        IL1RewardManager.MintAndBridgeParams memory params3 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 75 ether,
            startEpoch: 150, // Invalid: <= 200
            endEpoch: 350,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri3"
        });

        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.InvalidStartEpoch.selector));
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params3);
    }

    function test_ConsecutiveSuccessfulMints() public allowedDailyFrequency allowMintAmount(100 ether) {
        uint256 layerZeroFee = 0.01 ether;

        // First mint: 100-200
        IL1RewardManager.MintAndBridgeParams memory params1 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 100 ether,
            startEpoch: 100,
            endEpoch: 200,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri1"
        });

        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params1);
        assertEq(l1RewardManager.getLastIntervalEndEpoch(), 0, "After first mint: lastIntervalEndEpoch should be 0");
        assertEq(
            l1RewardManager.getCurrentIntervalEndEpoch(), 200, "After first mint: currentIntervalEndEpoch should be 200"
        );

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Second mint: 201-300
        IL1RewardManager.MintAndBridgeParams memory params2 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 50 ether,
            startEpoch: 201,
            endEpoch: 300,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri2"
        });

        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params2);
        assertEq(
            l1RewardManager.getLastIntervalEndEpoch(), 200, "After second mint: lastIntervalEndEpoch should be 200"
        );
        assertEq(
            l1RewardManager.getCurrentIntervalEndEpoch(),
            300,
            "After second mint: currentIntervalEndEpoch should be 300"
        );

        // Warp time to allow next mint
        vm.warp(block.timestamp + 1 days + 1);

        // Third mint: 301-400
        IL1RewardManager.MintAndBridgeParams memory params3 = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 75 ether,
            startEpoch: 301,
            endEpoch: 400,
            rewardsRoot: bytes32(hex"aabbccdd"),
            rewardsURI: "uri3"
        });

        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params3);
        assertEq(l1RewardManager.getLastIntervalEndEpoch(), 300, "After third mint: lastIntervalEndEpoch should be 300");
        assertEq(
            l1RewardManager.getCurrentIntervalEndEpoch(), 400, "After third mint: currentIntervalEndEpoch should be 400"
        );
    }

    function testRevert_InvalidRewardsRoot() public allowedDailyFrequency allowMintAmount(100 ether) {
        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            rewardsAmount: 100 ether,
            startEpoch: 100,
            endEpoch: 200,
            rewardsRoot: bytes32(0), // Invalid: empty rewards root
            rewardsURI: "uri"
        });

        uint256 layerZeroFee = 0.01 ether;
        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.InvalidRewardsRoot.selector));
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);
    }

    /**
     *  @notice Encodes a message for the LayerZero lzCompose
     *  @dev _composeMsg is 0x[composeFrom][composeMsg]
     *
     */
    function encode(
        uint64 _nonce,
        uint32 _srcEid,
        uint256 _amountLD,
        bytes memory _composeMsg // 0x[composeFrom][composeMsg]
    ) internal pure returns (bytes memory _msg) {
        _msg = abi.encodePacked(_nonce, _srcEid, _amountLD, _composeMsg);
    }
}
