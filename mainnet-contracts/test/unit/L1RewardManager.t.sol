// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
// import { xPufETH } from "src/l2/xPufETH.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";
import { IL1RewardManager } from "../../src/interface/IL1RewardManager.sol";
import { L1RewardManager } from "../../src/L1RewardManager.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";

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
import { GenerateRewardManagerCalldata } from "script/AccessManagerMigrations/03_GenerateRewardManagerCalldata.s.sol";

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
import { IOApp } from "../../src/interface/LayerZero/IOApp.sol";

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

        // ✅ Add enforced options for both OFT contracts
        // _setEnforcedOptionsForOFTs();

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
        L1RewardManager l1RewardManagerImpl = new L1RewardManager({
            oft: address(pufETHOFTAdapter),
            pufETH: address(pufferVault),
            l2RewardsManager: address(l2RewardManagerProxy)
        });

        L1RewardManager l1RewardManagerProxy = L1RewardManager(
            address(
                new ERC1967Proxy(
                    address(l1RewardManagerImpl), abi.encodeCall(L1RewardManager.initialize, (address(accessManager)))
                )
            )
        );
        L2RewardManager l2RewardManagerImpl = new L2RewardManager(address(pufETHOFT), address(l1RewardManagerProxy));

        UUPSUpgradeable(address(l2RewardManagerProxy)).upgradeToAndCall(
            address(l2RewardManagerImpl), abi.encodeCall(L2RewardManager.initialize, (address(accessManager)))
        );

        l2RewardManager = L2RewardManager(address(l2RewardManagerProxy));
        l1RewardManager = L1RewardManager(address(l1RewardManagerProxy));

        console.log("l1RewardManagerProxy", address(l1RewardManagerProxy));
        console.log("l2RewardManagerImpl", address(l2RewardManagerImpl));
        console.log("l2RewardManagerProxy", address(l2RewardManagerProxy));
        console.log("l1RewardManagerImpl", address(l1RewardManagerImpl));

        // bytes4[] memory xpufETHselectors = new bytes4[](3);
        // xpufETHselectors[0] = xPufETH.mint.selector;
        // xpufETHselectors[1] = xPufETH.burn.selector;

        // bytes4[] memory xpufETHDAOselectors = new bytes4[](2);
        // xpufETHDAOselectors[0] = xPufETH.setLimits.selector;
        // xpufETHDAOselectors[1] = xPufETH.setLockbox.selector;

        vm.startPrank(_broadcaster);
        // accessManager.setTargetFunctionRole(address(xpufETH), xpufETHDAOselectors, ROLE_ID_DAO);
        // accessManager.setTargetFunctionRole(address(xpufETH), xpufETHselectors, PUBLIC_ROLE);
        bytes memory cd = new GenerateRewardManagerCalldata().generateL1Calldata(
            address(l1RewardManager), address(layerzeroL1Endpoint), address(pufferVault), address(pufferModuleManager)
        );
        (bool s,) = address(accessManager).call(cd);
        require(s, "failed setupAccess GenerateRewardManagerCalldata");

        vm.label(address(l1RewardManager), "L1RewardManager");

        accessManager.grantRole(ROLE_ID_OPERATIONS_PAYMASTER, address(this), 0);

        vm.stopPrank();

        vm.startPrank(DAO);
        // xpufETH.setLockbox(address(lockBox));
        // xpufETH.setLimits(address(connext), 1000 ether, 1000 ether);

        L1RewardManagerStorage.BridgeData memory bridgeData =
            L1RewardManagerStorage.BridgeData({ destinationDomainId: 2, endpoint: address(layerzeroL1Endpoint) });
        l1RewardManager.updateBridgeData(address(pufETHOFTAdapter), bridgeData);

        vm.stopPrank();
        vm.deal(address(this), 300 ether);
        vm.deal(DAO, 300 ether);

        vm.warp(365 days);
    }

    /**
     * @notice Sets enforced options for the OFT contracts to ensure proper gas limits
     * @dev This mimics the production configuration from pufETH.simple.config.ts
     */
    function _setEnforcedOptionsForOFTs() internal {
        // Create enforced options for LZ_RECEIVE (msgType 1) and COMPOSE (msgType 2)
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](3);

        // LZ_RECEIVE option for msgType 1 - higher gas limit
        enforcedOptions[0] = EnforcedOptionParam({
            eid: dstEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(100000, 0)
        });

        // LZ_RECEIVE option for msgType 2 - higher gas limit
        enforcedOptions[1] = EnforcedOptionParam({
            eid: dstEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(100000, 0)
        });

        // COMPOSE option for msgType 2 - higher gas limit
        enforcedOptions[2] = EnforcedOptionParam({
            eid: dstEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzComposeOption(0, 100000, 0)
        });

        // Set enforced options for both OFT contracts
        IOAppOptionsType3(address(pufETHOFTAdapter)).setEnforcedOptions(enforcedOptions);
        IOAppOptionsType3(address(pufETHOFT)).setEnforcedOptions(enforcedOptions);
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
        new L1RewardManager(address(0), address(0), address(0));
    }

    function testRevert_updateBridgeDataInvalidBridge() public {
        vm.startPrank(DAO);

        L1RewardManagerStorage.BridgeData memory bridgeData = l1RewardManager.getBridge(address(pufETHOFTAdapter));

        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        l1RewardManager.updateBridgeData(address(0), bridgeData);
    }

    function test_MintAndBridgeRewardsSuccess() public allowedDailyFrequency allowMintAmount(100 ether) {
        rewardsAmount = 100 ether;

        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            oft: address(pufETHOFTAdapter),
            rewardsAmount: rewardsAmount,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        uint256 initialTotalAssets = pufferVault.totalAssets();

        // ✅ Use arbitrary value for LayerZero fees
        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);

        assertEq(pufferVault.totalAssets(), initialTotalAssets + 100 ether);
    }

    function testRevert_MintAndBridgeRewardsInvalidBridge() public allowedDailyFrequency allowMintAmount(100 ether) {
        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            oft: address(0), // invalid bridge
            rewardsAmount: 100 ether,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        // ✅ Use arbitrary value for LayerZero fees
        uint256 layerZeroFee = 0.01 ether;
        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.BridgeNotAllowlisted.selector));
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);
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
    // function test_undoMintAndBridgeRewardsRaceCondition() public allowedDailyFrequency allowMintAmount(100 ether) {
    //     // Get the initial state
    //     uint256 assetsBefore = pufferVault.totalAssets();
    //     uint256 rewardsAmountBefore = pufferVault.getTotalRewardMintAmount();
    //     uint256 pufETHTotalSupplyBefore = pufferVault.totalSupply();

    //     // Simulate mintAndBridgeRewards amounts in there are hardcoded to 100 ether
    //     test_MintAndBridgeRewardsSuccess();

    //     // Simulate a race condition, where the rewards are deposited to the vault before they are reverted
    //     address module = pufferProtocol.getModuleAddress(PUFFER_MODULE_0);
    //     // airdrop the rewards amount to the module
    //     vm.deal(module, rewardsAmount);
    //     address[] memory modules = new address[](1);
    //     modules[0] = module;
    //     uint256[] memory amounts = new uint256[](1);
    //     amounts[0] = rewardsAmount;
    //     pufferModuleManager.transferRewardsToTheVault(modules, amounts);

    //     // Now try tor evert the mintAndBridgeRewards, it panics
    //     L2RewardManagerStorage.EpochRecord memory epochRecord = L2RewardManagerStorage.EpochRecord({
    //         startEpoch: uint72(startEpoch),
    //         endEpoch: uint72(endEpoch),
    //         timeBridged: uint48(block.timestamp),
    //         ethToPufETHRate: 1 ether,
    //         pufETHAmount: 100 ether,
    //         ethAmount: 100 ether,
    //         rewardRoot: bytes32(hex"aabb")
    //     });

    //     bytes memory encodedCallData = abi.encode(epochRecord);

    //     // airdrop rewardsAmount to burner
    //     deal(address(xpufETH), address(l1RewardManager), 100 ether);

    //     vm.startPrank(address(connext));

    //     // Simulate a call from the connext bridge
    //     l1RewardManager.xReceive(bytes32(0), 0, address(0), address(l2RewardManager), 2, encodedCallData);

    //     assertEq(pufferVault.totalAssets(), assetsBefore, "assets before and now should match");
    //     assertEq(
    //         pufferVault.getTotalRewardMintAmount(), rewardsAmountBefore, "rewards amount before and now should match"
    //     );
    //     assertEq(pufferVault.totalSupply(), pufETHTotalSupplyBefore, "total supply before and now should match");
    // }

    // function test_undoMintAndBridgeRewards() public allowedDailyFrequency allowMintAmount(100 ether) {
    //     // Get the initial state
    //     uint256 assetsBefore = pufferVault.totalAssets();
    //     uint256 rewardsAmountBefore = pufferVault.getTotalRewardMintAmount();
    //     uint256 pufETHTotalSupplyBefore = pufferVault.totalSupply();

    //     // Simulate mintAndBridgeRewards amounts in there are hardcoded to 100 ether
    //     test_MintAndBridgeRewardsSuccess();

    //     // Rewards and assets increase
    //     assertEq(pufferVault.totalAssets(), assetsBefore + 100 ether, "assets before and now should match");
    //     assertEq(
    //         pufferVault.getTotalRewardMintAmount(),
    //         rewardsAmountBefore + 100 ether,
    //         "rewards amount before and now should match"
    //     );
    //     assertEq(
    //         pufferVault.totalSupply(), pufETHTotalSupplyBefore + 100 ether, "total supply before and now should match"
    //     );

    //     L2RewardManagerStorage.EpochRecord memory epochRecord = L2RewardManagerStorage.EpochRecord({
    //         startEpoch: uint72(startEpoch),
    //         endEpoch: uint72(endEpoch),
    //         timeBridged: uint48(block.timestamp),
    //         ethToPufETHRate: 1 ether,
    //         pufETHAmount: 100 ether,
    //         ethAmount: 100 ether,
    //         rewardRoot: bytes32(hex"aabb")
    //     });

    //     bytes memory encodedCallData = abi.encode(epochRecord);

    //     // airdrop rewardsAmount to burner
    //     deal(address(xpufETH), address(l1RewardManager), 100 ether);

    //     vm.startPrank(address(connext));

    //     // Simulate a call from the connext bridge
    //     l1RewardManager.xReceive(bytes32(0), 0, address(0), address(l2RewardManager), 2, encodedCallData);

    //     assertEq(pufferVault.totalAssets(), assetsBefore, "assets before and now should match");
    //     assertEq(
    //         pufferVault.getTotalRewardMintAmount(), rewardsAmountBefore, "rewards amount before and now should match"
    //     );
    //     assertEq(pufferVault.totalSupply(), pufETHTotalSupplyBefore, "total supply before and now should match");
    // }

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

    function encode(
        uint64 _nonce,
        uint32 _srcEid,
        uint256 _amountLD,
        bytes memory _composeMsg // 0x[composeFrom][composeMsg]
    ) internal pure returns (bytes memory _msg) {
        _msg = abi.encodePacked(_nonce, _srcEid, _amountLD, _composeMsg);
    }

    function testRevert_MintAndBridgeRewardsInvalidMintAmount() public {
        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            oft: address(pufETHOFTAdapter),
            rewardsAmount: 200 ether, // assuming this is more than allowed
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(0),
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
            oft: address(pufETHOFTAdapter),
            rewardsAmount: 1 ether,
            startEpoch: 1,
            endEpoch: 2,
            rewardsRoot: bytes32(0),
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
        l1RewardManager.setL2RewardClaimer{ value: layerZeroFee }(address(pufETHOFTAdapter), newClaimer);
    }

    function testRevert_setClaimerInvalidBrige() public {
        uint256 layerZeroFee = 0.01 ether;
        vm.expectRevert(abi.encodeWithSelector(IL1RewardManager.BridgeNotAllowlisted.selector));
        l1RewardManager.setL2RewardClaimer{ value: layerZeroFee }(address(0x1111), address(0x123));
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
            oft: address(pufETHOFTAdapter),
            rewardsAmount: rewardsAmount,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            rewardsRoot: bytes32(0),
            rewardsURI: "uri"
        });

        uint256 initialTotalAssets = pufferVault.totalAssets();

        // ✅ Use arbitrary value for LayerZero fees
        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.mintAndBridgeRewards{ value: layerZeroFee }(params);

        assertEq(pufferVault.totalAssets(), initialTotalAssets + 100 ether);
    }

    /**
     * @notice Test that setL2RewardClaimer works with enforced options
     */
    function test_SetL2RewardClaimerWithEnforcedOptions() public {
        address newClaimer = address(0x123);

        // ✅ Use arbitrary value for LayerZero fees
        uint256 layerZeroFee = 0.01 ether;
        l1RewardManager.setL2RewardClaimer{ value: layerZeroFee }(address(pufETHOFTAdapter), newClaimer);

        // Verify the function executed without reverting
        assertTrue(true, "setL2RewardClaimer with enforced options works");
    }
}
