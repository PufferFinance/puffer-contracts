// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { PufferDepositor } from "src/PufferDepositor.sol";
import { Timelock } from "src/Timelock.sol";
import { PufferVaultV5 } from "src/PufferVaultV5.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { XERC20Lockbox } from "src/XERC20Lockbox.sol";
import { stETHMock } from "test/mocks/stETHMock.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PufferDeployment } from "src/structs/PufferDeployment.sol";
import { DeployPufETH } from "script/DeployPufETH.s.sol";
import { ROLE_ID_DAO } from "script/Roles.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PufferRevenueDepositorMock } from "test/mocks/PufferRevenueDepositorMock.sol";
import { MockPufferOracle } from "test/mocks/MockPufferOracle.sol";
import { PufferVaultV5Tests } from "test/mocks/PufferVaultV5Tests.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";

contract xPufETHTest is Test {
    PufferDepositor public pufferDepositor;
    PufferVaultV5 public pufferVault;
    AccessManager public accessManager;
    stETHMock public stETH;
    Timelock public timelock;
    xPufETH public xPufETHProxy;
    XERC20Lockbox public xERC20Lockbox;
    IWETH public weth;
    address communityMultisig = makeAddr("communityMultisig");

    function setUp() public {
        PufferDeployment memory deployment = new DeployPufETH().run();
        pufferDepositor = PufferDepositor(payable(deployment.pufferDepositor));
        pufferVault = PufferVaultV5(payable(deployment.pufferVault));
        accessManager = AccessManager(payable(deployment.accessManager));
        stETH = stETHMock(payable(deployment.stETH));
        timelock = Timelock(payable(deployment.timelock));
        weth = IWETH(payable(deployment.weth));
        // Deploy implementation
        xPufETH newImplementation = new xPufETH();

        // Deploy proxy
        vm.expectEmit(true, true, true, true);
        emit Initializable.Initialized(1);
        xPufETHProxy = xPufETH(
            address(
                new ERC1967Proxy{ salt: bytes32("xPufETH") }(
                    address(newImplementation), abi.encodeCall(xPufETH.initialize, (address(accessManager)))
                )
            )
        );

        // Deploy the lockbox
        xERC20Lockbox = new XERC20Lockbox(address(xPufETHProxy), address(deployment.pufferVault));

        // Setup AccessManager stuff
        // Setup access
        bytes4[] memory daoSelectors = new bytes4[](2);
        daoSelectors[0] = xPufETH.setLockbox.selector;
        daoSelectors[1] = xPufETH.setLimits.selector;

        bytes4[] memory lockBoxSelectors = new bytes4[](2);
        lockBoxSelectors[0] = xPufETH.mint.selector;
        lockBoxSelectors[1] = xPufETH.burn.selector;

        bytes4[] memory vaultSelectors = new bytes4[](3);
        vaultSelectors[0] = PufferVaultV5.setExitFeeBasisPoints.selector;
        vaultSelectors[1] = PufferVaultV5.setTreasuryExitFeeBasisPoints.selector;
        vaultSelectors[2] = PufferVaultV5.setTreasury.selector;

        // Public selectors
        vm.startPrank(address(timelock));
        accessManager.setTargetFunctionRole(address(xPufETHProxy), lockBoxSelectors, accessManager.PUBLIC_ROLE());
        accessManager.setTargetFunctionRole(address(xPufETHProxy), daoSelectors, ROLE_ID_DAO);
        accessManager.setTargetFunctionRole(address(pufferVault), vaultSelectors, ROLE_ID_DAO);
        accessManager.grantRole(ROLE_ID_DAO, address(this), 0); // this contract is the dao for simplicity
        accessManager.grantRole(ROLE_ID_DAO, communityMultisig, 0); // this contract is the dao for simplicity
        vm.stopPrank();

        _useTestVersion(deployment);

        // Set the Lockbox)
        xPufETHProxy.setLockbox(address(xERC20Lockbox));

        // Mint mock weth to this contract
        deal(address(this), type(uint128).max);
        weth.deposit{ value: type(uint128).max / 2 }();
    }

    // We deposit pufETH to get xpufETH to this contract using .depositTo
    function test_mint_xpufETH(uint8 amount) public {
        weth.approve(address(pufferVault), type(uint256).max);
        pufferVault.deposit(uint256(amount), address(this));

        pufferVault.approve(address(xERC20Lockbox), type(uint256).max);
        xERC20Lockbox.depositTo(address(this), uint256(amount));
        assertEq(xPufETHProxy.balanceOf(address(this)), uint256(amount), "got xpufETH");
        assertEq(pufferVault.balanceOf(address(xERC20Lockbox)), uint256(amount), "pufETH is in the lockbox");
    }

    // We deposit pufETH to get xpufETH to this contract using .deposit
    function test_deposit_pufETH_for_xpufETH(uint8 amount) public {
        weth.approve(address(pufferVault), type(uint256).max);
        pufferVault.deposit(uint256(amount), address(this));

        pufferVault.approve(address(xERC20Lockbox), type(uint256).max);
        xERC20Lockbox.deposit(uint256(amount));
        assertEq(xPufETHProxy.balanceOf(address(this)), uint256(amount), "got xpufETH");
        assertEq(pufferVault.balanceOf(address(xERC20Lockbox)), uint256(amount), "pufETH is in the lockbox");
    }

    // We withdraw pufETH to Bob
    function test_mint_and_burn_xpufETH(uint8 amount) public {
        address bob = makeAddr("bob");
        test_mint_xpufETH(amount);

        xPufETHProxy.approve(address(xERC20Lockbox), type(uint256).max);
        xERC20Lockbox.withdrawTo(bob, uint256(amount));
        assertEq(pufferVault.balanceOf(bob), amount, "bob got pufETH");
    }

    // We withdraw to self
    function test_mint_and_withdraw_xpufETH(uint8 amount) public {
        test_mint_xpufETH(amount);

        xPufETHProxy.approve(address(xERC20Lockbox), type(uint256).max);

        uint256 pufEThBalanceBefore = pufferVault.balanceOf(address(this));

        xERC20Lockbox.withdraw(uint256(amount));
        assertEq(pufferVault.balanceOf(address(this)), pufEThBalanceBefore + amount, "we got pufETH");
    }

    function test_nativeReverts() public {
        vm.expectRevert();
        xERC20Lockbox.depositNativeTo(address(0));

        vm.expectRevert();
        xERC20Lockbox.depositNative();
    }

    function _useTestVersion(PufferDeployment memory deployment) private {
        vm.startPrank(address(timelock));

        vm.stopPrank();

        MockPufferOracle mockOracle = new MockPufferOracle();
        PufferRevenueDepositorMock revenueDepositor = new PufferRevenueDepositorMock();
        PufferVaultV5 pufferVaultNonBlocking = new PufferVaultV5Tests({
            stETH: stETH,
            lidoWithdrawalQueue: ILidoWithdrawalQueue(deployment.lidoWithdrawalQueueMock),
            weth: IWETH(deployment.weth),
            oracle: mockOracle,
            revenueDepositor: revenueDepositor
        });

        vm.startPrank(communityMultisig);

        UUPSUpgradeable(pufferVault).upgradeToAndCall(address(pufferVaultNonBlocking), "");
        pufferVault.setExitFeeBasisPoints(0);
        vm.stopPrank();
    }
}
