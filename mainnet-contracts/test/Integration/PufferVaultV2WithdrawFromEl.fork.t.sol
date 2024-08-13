// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { PufferVaultV2 } from "../../src/PufferVaultV2.sol";
import { IStETH } from "../../src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "../../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "../../src/interface/Other/IWETH.sol";
import { IStrategy } from "../../src/interface/EigenLayer/IStrategy.sol";
import { IEigenLayer } from "../../src/interface/EigenLayer/IEigenLayer.sol";
import { IDelegationManager } from "../../src/interface/EigenLayer/IDelegationManager.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IPufferOracle } from "../../src/interface/IPufferOracle.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { PufferDeployment } from "../../src/structs/PufferDeployment.sol";
import { DeployPufETH } from "script/DeployPufETH.s.sol";
import { PufferDepositor } from "../../src/PufferDepositor.sol";
import { PufferVault } from "../../src/PufferVault.sol";
import { Timelock } from "../../src/Timelock.sol";
import { GenerateAccessManagerCallData } from "script/GenerateAccessManagerCallData.sol";
import { MockPufferOracle } from "../../test/mocks/MockPufferOracle.sol";

contract PufferVaultWithdrawalTest is Test {
    PufferVaultV2 newImpl;

    PufferVault pufferVault;
    AccessManager accessManager;
    Timelock timelock;
    IStETH stETH;

    address pufferDevWallet = 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;
    address operations = 0x5568b309259131D3A7c128700195e0A1C94761A0;
    address community = 0xf9F846FA49e79BE8d74c68CDC01AaaFfBBf8177F;

    address pufferDepositor;

    function setUp() public {
        // Cancun upgrade
        vm.createSelectFork(vm.rpcUrl("holesky"), 1304211);

        // Dep
        PufferDeployment memory deployment = new DeployPufETH().run();
        pufferDepositor = deployment.pufferDepositor;
        pufferVault = PufferVault(payable(deployment.pufferVault));
        accessManager = AccessManager(payable(deployment.accessManager));
        timelock = Timelock(payable(deployment.timelock));

        stETH = IStETH(address(0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034));
        IWETH weth = IWETH(0xD6eF375Ad62f1d5BC06479fD0c7DCEF28e5Dc898);
        ILidoWithdrawalQueue lidoWithdrawalQueue = ILidoWithdrawalQueue(0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50);
        IStrategy stETHStrategy = IStrategy(0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3);
        IEigenLayer eigenStrategyManager = IEigenLayer(0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6);
        MockPufferOracle oracle = new MockPufferOracle();
        IDelegationManager delegationManager = IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7);

        newImpl = new PufferVaultV2(
            stETH,
            weth,
            lidoWithdrawalQueue,
            stETHStrategy,
            eigenStrategyManager,
            IPufferOracle(address(oracle)),
            delegationManager
        );
    }

    // Update contracts and setup access
    function _upgradeContracts() internal {
        // Community multisig
        vm.startPrank(community);
        vm.expectEmit(true, true, true, true);
        emit ERC1967Utils.Upgraded(address(newImpl));
        UUPSUpgradeable(pufferVault).upgradeToAndCall(address(newImpl), abi.encodeCall(PufferVaultV2.initialize, ()));

        // Setup access
        bytes memory encodedMulticall = new GenerateAccessManagerCallData().run(address(pufferVault), pufferDepositor);

        (bool success,) = address(timelock).call(
            abi.encodeWithSelector(Timelock.executeTransaction.selector, address(accessManager), encodedMulticall, 1)
        );
        require(success, "failed upgrade tx");
        // Timelock is the owner of the AccessManager
        // timelock.executeTransaction(address(accessManagerß), encodedMulticall, 1);
    }
}
