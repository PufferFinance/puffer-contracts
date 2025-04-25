// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "erc4626-tests/ERC4626.test.sol";
import { IStETH } from "../../src/interface/Lido/IStETH.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { PufferDepositor } from "../../src/PufferDepositor.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { stETHMock } from "../mocks/stETHMock.sol";
import { WETH9 } from "../mocks/WETH9.sol";
import { MockPufferOracle } from "../mocks/MockPufferOracle.sol";
import { ILidoWithdrawalQueue } from "../../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";
import { IPufferRevenueDepositor } from "../../src/interface/IPufferRevenueDepositor.sol";
import { PufferVaultV5Tests } from "../mocks/PufferVaultV5Tests.sol";
import { PufferDeployment } from "../../src/structs/PufferDeployment.sol";
import { DeployPufETH } from "script/DeployPufETH.s.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract PufETHTest is ERC4626Test {
    PufferDepositor public pufferDepositor;
    PufferVaultV5 public pufferVault;
    AccessManager public accessManager;
    IStETH public stETH;
    IWETH public weth;

    address operationsMultisig = makeAddr("operations");
    address communityMultisig = makeAddr("communityMultisig");

    function setUp() public override {
        PufferDeployment memory deployment = new DeployPufETH().run();

        pufferDepositor = PufferDepositor(payable(deployment.pufferDepositor));
        pufferVault = PufferVaultV5(payable(deployment.pufferVault));
        accessManager = AccessManager(payable(deployment.accessManager));
        stETH = IStETH(payable(deployment.stETH));
        weth = IWETH(payable(deployment.weth));

        _useTestVersion(deployment);


        console.log('pufferVault', address(pufferVault));
        // log puffer vault implementation
        console.log('pufferVaultImplementation', address(uint160(uint256(vm.load(address(pufferVault), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)))));

        // Check vault underlying is weth
        assertEq(pufferVault.asset(), address(deployment.weth), "bad asset");

        _underlying_ = address(deployment.weth);
        _vault_ = address(pufferVault);
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;

    }

    function test_erc4626_interface() public {
        WETH9(payable(address(weth))).deposit{value: 2000 ether}();
        weth.approve(address(pufferVault), type(uint256).max);

        // Deposit works
        assertEq(pufferVault.deposit(1000 ether, address(this)), 1000 ether, "deposit");
        assertEq(pufferVault.mint(1000 ether, address(this)), 1000 ether, "mint");

        // Getters work
        assertEq(pufferVault.asset(), address(weth), "bad asset");
        assertEq(pufferVault.totalAssets(), weth.balanceOf(address(pufferVault)), "bad assets");
        assertEq(pufferVault.convertToShares(1 ether), 1 ether, "bad conversion");
        assertEq(pufferVault.convertToAssets(1 ether), 1 ether, "bad conversion shares");
        assertEq(pufferVault.maxDeposit(address(5)), type(uint256).max, "bad max deposit");
        assertEq(pufferVault.previewDeposit(1 ether), 1 ether, "preview shares");
        assertEq(pufferVault.maxMint(address(5)), type(uint256).max, "max mint");
        assertEq(pufferVault.previewMint(1 ether), 1 ether, "preview mint");
        assertEq(pufferVault.previewWithdraw(1000 ether), 1000 ether, "preview withdraw");
        assertEq(pufferVault.maxRedeem(address(this)), 2000 ether, "maxRedeem");
        assertEq(pufferVault.previewRedeem(1000 ether), 1000 ether, "previewRedeem");
    }

    function test_roles_setup() public {
        address msgSender = makeAddr("random");
        vm.startPrank(msgSender);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, msgSender));
        pufferVault.upgradeToAndCall(address(pufferDepositor), "");
        vm.stopPrank();
    }

    // All withdrawals are disabled, we override these tests to not revert
    function test_RT_deposit_redeem(Init memory init, uint256 assets) public override { }
    function test_RT_deposit_withdraw(Init memory init, uint256 assets) public override { }
    function test_RT_mint_redeem(Init memory init, uint256 shares) public override { }
    function test_RT_mint_withdraw(Init memory init, uint256 shares) public override { }
    function test_RT_redeem_deposit(Init memory init, uint256 shares) public override { }
    function test_RT_redeem_mint(Init memory init, uint256 shares) public override { }
    function test_RT_withdraw_deposit(Init memory init, uint256 assets) public override { }
    function test_RT_withdraw_mint(Init memory init, uint256 assets) public override { }
    function test_previewRedeem(Init memory init, uint256 shares) public override { }
    function test_previewWithdraw(Init memory init, uint256 assets) public override { }
    function test_redeem(Init memory init, uint256 shares, uint256 allowance) public override { }
    function test_withdraw(Init memory init, uint256 assets, uint256 allowance) public override { }

    function _useTestVersion(PufferDeployment memory deployment) private {

        MockPufferOracle mockOracle = new MockPufferOracle();

        PufferVaultV5 pufferVaultNonBlocking = new PufferVaultV5Tests({
            stETH: stETH,
            lidoWithdrawalQueue: ILidoWithdrawalQueue(deployment.lidoWithdrawalQueueMock),
            weth: IWETH(deployment.weth),
            oracle: mockOracle,
            revenueDepositor: IPufferRevenueDepositor(address(0))
        });

        console.log("pufferVaultNonBlocking", address(pufferVaultNonBlocking));

        vm.startPrank(communityMultisig);

        UUPSUpgradeable(pufferVault).upgradeToAndCall(address(pufferVaultNonBlocking), "");

        vm.stopPrank();
    }
}
