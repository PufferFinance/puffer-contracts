// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/PufferPointTokenWrapper.sol";
import "./mocks/MockToken.sol";
import "./mocks/MockCoreBorrow.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PufferPointTokenWrapperTest is Test {
    PufferPointTokenWrapper public tokenWrapper;
    MockToken public angle;
    MockCoreBorrow public core;

    address public deployer = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public governor = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
    address public guardian = 0x0C2553e4B9dFA9f83b1A6D3EAB96c4bAaB42d430;
    address public distributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address public distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
    address public feeRecipient = 0xeaC6A75e19beB1283352d24c0311De865a867DAB;

    uint32 public constant CLIFF_DURATION = 2592000;

    function setUp() public {
        // Fork mainnet at specific block
        vm.createSelectFork("mainnet", 21313975);

        // Setup impersonated accounts
        vm.startPrank(governor);
        vm.deal(governor, 100 ether);
        vm.stopPrank();

        vm.startPrank(guardian);
        vm.deal(guardian, 100 ether);
        vm.stopPrank();

        vm.startPrank(distributor);
        vm.deal(distributor, 100 ether);
        vm.stopPrank();

        // Deploy contracts
        angle = new MockToken("ANGLE", "ANGLE", 18);
        core = new MockCoreBorrow();

        // Setup core roles
        core.toggleGuardian(guardian);
        core.toggleGovernor(governor);

        // Deploy and initialize token wrapper using the proxy pattern
        PufferPointTokenWrapper implementation = new PufferPointTokenWrapper();
        bytes memory initData = abi.encodeWithSelector(
            PufferPointTokenWrapper.initialize.selector,
            address(angle),
            CLIFF_DURATION,
            IAccessControlManager(address(core)),
            distributionCreator
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        tokenWrapper = PufferPointTokenWrapper(address(proxy));

        // Mint initial tokens
        angle.mint(alice, 1000 ether);
    }

    function test_claimRewards() public {
        // Initial setup
        vm.startPrank(alice);
        angle.approve(address(tokenWrapper), type(uint256).max);
        tokenWrapper.transfer(distributor, 1 ether);
        vm.stopPrank();

        // First transfer from distributor to bob
        vm.startPrank(distributor);
        tokenWrapper.transfer(bob, 0.5 ether);
        vm.stopPrank();
        uint256 endData = block.timestamp;

        // Initial state verification
        assertEq(tokenWrapper.balanceOf(bob), 0);
        assertEq(tokenWrapper.balanceOf(distributor), 0.5 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 1 ether);

        // Check initial vesting data
        (VestingID[] memory vestings, uint256 nextClaimIndex) = tokenWrapper.getUserVestings(bob);
        assertEq(vestings[0].amount, 0.5 ether);
        assertEq(vestings[0].unlockTimestamp, endData + CLIFF_DURATION);
        assertEq(nextClaimIndex, 0);

        // Test claiming before cliff
        vm.warp(block.timestamp + CLIFF_DURATION / 2);
        assertEq(tokenWrapper.claimable(bob), 0);

        // Test claiming after cliff
        vm.warp(block.timestamp + CLIFF_DURATION * 2);
        assertEq(tokenWrapper.claimable(bob), 0.5 ether);
        tokenWrapper.claim(bob);
        assertEq(angle.balanceOf(bob), 0.5 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 0.5 ether);

        // Check updated vesting data
        (vestings, nextClaimIndex) = tokenWrapper.getUserVestings(bob);
        assertEq(vestings[0].amount, 0.5 ether);
        assertEq(vestings[0].unlockTimestamp, endData + CLIFF_DURATION);
        assertEq(nextClaimIndex, 1);

        // Second transfer to bob
        vm.startPrank(distributor);
        tokenWrapper.transfer(bob, 0.2 ether);
        vm.stopPrank();
        uint256 endTime2 = block.timestamp;
        assertEq(tokenWrapper.balanceOf(distributor), 0.3 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 0.5 ether);

        // Check second vesting data
        (vestings, nextClaimIndex) = tokenWrapper.getUserVestings(bob);
        assertEq(vestings[1].amount, 0.2 ether);
        assertEq(vestings[1].unlockTimestamp, endTime2 + CLIFF_DURATION);
        assertEq(nextClaimIndex, 1);

        // Third transfer to bob
        vm.warp(block.timestamp + CLIFF_DURATION / 2);
        assertEq(tokenWrapper.claimable(bob), 0);
        vm.startPrank(distributor);
        tokenWrapper.transfer(bob, 0.12 ether);
        vm.stopPrank();
        uint256 endTime3 = block.timestamp;
        assertEq(tokenWrapper.balanceOf(distributor), 0.18 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 0.5 ether);

        // Check third vesting data
        (vestings, nextClaimIndex) = tokenWrapper.getUserVestings(bob);
        assertEq(vestings[1].amount, 0.2 ether);
        assertEq(vestings[1].unlockTimestamp, endTime2 + CLIFF_DURATION);
        assertEq(nextClaimIndex, 1);
        assertEq(vestings[2].amount, 0.12 ether);
        assertEq(vestings[2].unlockTimestamp, endTime3 + CLIFF_DURATION);

        // Test partial vesting completion
        vm.warp(block.timestamp + CLIFF_DURATION * 3 / 4);
        assertEq(tokenWrapper.claimable(bob), 0.2 ether);
        tokenWrapper.claim(bob);
        assertEq(tokenWrapper.claimable(bob), 0);
        assertEq(angle.balanceOf(bob), 0.7 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 0.3 ether);

        // Fourth transfer to bob
        vm.startPrank(distributor);
        tokenWrapper.transfer(bob, 0.1 ether);
        vm.stopPrank();
        uint256 endTime4 = block.timestamp;
        assertEq(tokenWrapper.balanceOf(distributor), 0.08 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 0.3 ether);

        // Check fourth vesting data
        (vestings, nextClaimIndex) = tokenWrapper.getUserVestings(bob);
        assertEq(vestings[3].amount, 0.1 ether);
        assertEq(vestings[3].unlockTimestamp, endTime4 + CLIFF_DURATION);
        assertEq(nextClaimIndex, 2);

        // Transfer to alice
        vm.startPrank(distributor);
        tokenWrapper.transfer(alice, 0.05 ether);
        vm.stopPrank();
        uint256 endTime5 = block.timestamp;
        assertEq(tokenWrapper.balanceOf(distributor), 0.03 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 0.3 ether);

        // Check alice's vesting data
        (vestings, nextClaimIndex) = tokenWrapper.getUserVestings(alice);
        assertEq(vestings[0].amount, 0.05 ether);
        assertEq(vestings[0].unlockTimestamp, endTime5 + CLIFF_DURATION);
        assertEq(nextClaimIndex, 0);

        // Final claims
        vm.warp(block.timestamp + CLIFF_DURATION * 2);
        assertEq(tokenWrapper.claimable(bob), 0.22 ether);
        assertEq(tokenWrapper.claimable(alice), 0.05 ether);

        tokenWrapper.claim(bob);
        assertEq(tokenWrapper.balanceOf(distributor), 0.03 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 0.08 ether);
        assertEq(angle.balanceOf(bob), 0.92 ether);

        // Check final vesting states
        (vestings, nextClaimIndex) = tokenWrapper.getUserVestings(bob);
        assertEq(nextClaimIndex, 4);
        assertEq(tokenWrapper.claimable(bob), 0);

        tokenWrapper.claim(alice);
        (vestings, nextClaimIndex) = tokenWrapper.getUserVestings(alice);
        assertEq(nextClaimIndex, 1);
        assertEq(tokenWrapper.balanceOf(distributor), 0.03 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 0.03 ether);
        assertEq(angle.balanceOf(bob), 0.92 ether);
        assertEq(angle.balanceOf(alice), 999.05 ether);

        // Final claims (should not change anything)
        tokenWrapper.claim(alice);
        tokenWrapper.claim(bob);
        (vestings, nextClaimIndex) = tokenWrapper.getUserVestings(alice);
        assertEq(nextClaimIndex, 1);
        (vestings, nextClaimIndex) = tokenWrapper.getUserVestings(bob);
        assertEq(nextClaimIndex, 4);
        assertEq(tokenWrapper.balanceOf(distributor), 0.03 ether);
        assertEq(angle.balanceOf(address(tokenWrapper)), 0.03 ether);
        assertEq(angle.balanceOf(bob), 0.92 ether);
        assertEq(angle.balanceOf(alice), 999.05 ether);
    }
}
