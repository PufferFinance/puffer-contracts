// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { L2RewardManager } from "l2-contracts/src/L2RewardManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { NoImplementation } from "../src/NoImplementation.sol";
import { L1RewardManager } from "src/L1RewardManager.sol";
import { BridgeMock } from "l2-contracts/test/mocks/BridgeMock.sol";
import { GenerateAccessManagerCalldata3 } from "script/AccessManagerMigrations/GenerateAccessManagerCalldata3.s.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { xPufETH } from "src/l2/xPufETH.sol";
import { XERC20Lockbox } from "mainnet-contracts/src/XERC20Lockbox.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PUBLIC_ROLE } from "./Roles.sol";
import { IL1RewardManager } from "src/interface/IL1RewardManager.sol";
import { L1RewardManagerStorage } from "src/L1RewardManagerStorage.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";
import { PufferVaultV3 } from "src/PufferVaultV3.sol";
import { IStETH } from "src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "src/interface/Other/IWETH.sol";
import { IStrategy } from "src/interface/EigenLayer/IStrategy.sol";
import { IEigenLayer } from "src/interface/EigenLayer/IEigenLayer.sol";
import { IPufferOracle } from "src/interface/IPufferOracle.sol";
import { IDelegationManager } from "src/interface/EigenLayer/IDelegationManager.sol";
import { GenerateBridgeMockCalldata } from "mainnet-contracts/script/AccessManagerMigrations/04_HoleskyBridgeMock.sol";

/**
 * @dev
 * To run the simulation do the following:
 *         forge script script/DeployFWRHolesky.s.sol:DeployFWRHolesky -vvvv --account
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 */
contract DeployFWRHolesky is DeployerHelper {
    address l1RewardManagerProxy;
    address l2RewardManagerProxy;

    function run() public {
        vm.createSelectFork(vm.rpcUrl("holesky"));
        vm.startBroadcast();

        address bridge = _deployBridgeMock();
        _deployAndUpgradePufferVault();
        _deployL1RewardManagerProxy(bridge);
        (address xpufETHProxy, address lockbox) = _deployAndConfigureXPufETH(bridge);
        _deployL2RewardManager(bridge, xpufETHProxy);
        _deployAndUpgradeL1RewardManager(bridge, xpufETHProxy, lockbox);

        vm.stopBroadcast();
    }

    function _deployBridgeMock() internal returns (address) {
        return address(new BridgeMock(_getAccessManager()));
    }

    function _deployAndUpgradePufferVault() internal {
        PufferVaultV3 protocolImplementation = new PufferVaultV3(
            IStETH(_getStETH()),
            IWETH(_getWETH()),
            ILidoWithdrawalQueue(_getLidoWithdrawalQueue()),
            IStrategy(_getStETHStrategy()),
            IEigenLayer(_getEigenLayerStrategyManager()),
            IPufferOracle(_getPufferOracle()),
            IDelegationManager(_getEigenDelegationManager())
        );

        UUPSUpgradeable(_getPufferVault()).upgradeToAndCall(address(protocolImplementation), "");
    }

    function _deployL1RewardManagerProxy(address bridge) internal {
        address noImpl = address(new NoImplementation());
        l1RewardManagerProxy = address(new ERC1967Proxy(noImpl, ""));
        vm.label(address(l1RewardManagerProxy), "l1RewardManagerProxy");

        bytes memory l1AccessManagerCalldata = new GenerateAccessManagerCalldata3().generateL1Calldata({
            l1RewardManagerProxy: l1RewardManagerProxy,
            l1Bridge: bridge,
            pufferVaultProxy: _getPufferVault(),
            pufferModuleManagerProxy: _getPufferModuleManager()
        });

        (bool s,) = address(_getAccessManager()).call(l1AccessManagerCalldata);
        require(s, "failed access manager 0");

        console.log("L1 Access Manager Calldata");
        console.logBytes(l1AccessManagerCalldata);
    }

    function _deployAndConfigureXPufETH(address bridge) internal returns (address, address) {
        xPufETH xPufETHProxy = xPufETH(
            address(
                new ERC1967Proxy{ salt: bytes32("xPufETH") }(
                    address(new xPufETH()), abi.encodeCall(xPufETH.initialize, (_getAccessManager()))
                )
            )
        );

        XERC20Lockbox xERC20Lockbox = new XERC20Lockbox({ xerc20: address(xPufETHProxy), erc20: _getPufferVault() });

        bytes4[] memory publicSelectors = new bytes4[](2);
        publicSelectors[0] = xPufETH.mint.selector;
        publicSelectors[1] = xPufETH.burn.selector;

        AccessManager(_getAccessManager()).setTargetFunctionRole(address(xPufETHProxy), publicSelectors, PUBLIC_ROLE);

        xPufETHProxy.setLockbox(address(xERC20Lockbox));

        bytes memory setLimitsCalldata =
            abi.encodeWithSelector(xPufETH.setLimits.selector, bridge, type(uint104).max, type(uint104).max);

        AccessManager(_getAccessManager()).execute(address(xPufETHProxy), setLimitsCalldata);

        return (address(xPufETHProxy), address(xERC20Lockbox));
    }

    function _deployL2RewardManager(address bridge, address xPufETHProxy) internal {
        L2RewardManager newImplementation = new L2RewardManager(address(xPufETHProxy), address(l1RewardManagerProxy));

        console.log("L2RewardManager Implementation", address(newImplementation));

        l2RewardManagerProxy = address(
            new ERC1967Proxy(
                address(newImplementation), abi.encodeCall(L2RewardManager.initialize, (_getAccessManager()))
            )
        );
        vm.makePersistent(l2RewardManagerProxy);

        console.log("L2RewardManager Proxy", address(l2RewardManagerProxy));
        vm.label(address(l2RewardManagerProxy), "L2RewardManagerProxy");
        vm.label(address(newImplementation), "L2RewardManagerImplementation");

        bytes memory l2AccessManagerCalldata = new GenerateAccessManagerCalldata3().generateL2Calldata({
            l2RewardManagerProxy: l2RewardManagerProxy,
            l2Bridge: bridge
        });

        (bool s,) = address(_getAccessManager()).call(l2AccessManagerCalldata);
        require(s, "failed access manager 1");

        console.log("L2 Access Manager Calldata");
        console.logBytes(l2AccessManagerCalldata);
    }

    function _deployAndUpgradeL1RewardManager(address bridge, address xPufETHProxy, address xERC20Lockbox) internal {
        L1RewardManager l1ReeardManagerImpl = new L1RewardManager({
            XpufETH: address(xPufETHProxy),
            pufETH: _getPufferVault(),
            lockbox: address(xERC20Lockbox),
            l2RewardsManager: l2RewardManagerProxy
        });

        vm.label(address(l1ReeardManagerImpl), "l1ReeardManagerImpl");

        UUPSUpgradeable(l1RewardManagerProxy).upgradeToAndCall(
            address(l1ReeardManagerImpl), abi.encodeCall(L1RewardManager.initialize, (_getAccessManager()))
        );

        bytes memory bridgeAccess = new GenerateBridgeMockCalldata().generateBridgeMockCalldata(
            bridge, l1RewardManagerProxy, l2RewardManagerProxy
        );

        (bool s,) = address(_getAccessManager()).call(bridgeAccess);
        require(s, "failed access manager 2");

        _updateBridgeData(bridge, L1RewardManager(l1RewardManagerProxy), L2RewardManager(l2RewardManagerProxy));

        _executeMintAndBridge(bridge, L1RewardManager(l1RewardManagerProxy));

        _executeFreezeAndRevert(bridge, L2RewardManager(l2RewardManagerProxy));
    }

    function _executeFreezeAndRevert(address bridge, L2RewardManager l2RewardManager) internal {
        l2RewardManager.freezeAndRevertInterval(bridge, 1, 10);
    }

    function _updateBridgeData(address bridge, L1RewardManager l1RewardManager, L2RewardManager l2RewardManager)
        internal
    {
        L2RewardManagerStorage.BridgeData memory bridgeData =
            L2RewardManagerStorage.BridgeData({ destinationDomainId: 1 });

        l2RewardManager.updateBridgeData(bridge, bridgeData);

        L1RewardManagerStorage.BridgeData memory bridgeDataL1 =
            L1RewardManagerStorage.BridgeData({ destinationDomainId: 2 });

        l1RewardManager.updateBridgeData(bridge, bridgeDataL1);
    }

    function _executeMintAndBridge(address bridge, L1RewardManager l1RewardManager) internal {
        l1RewardManager.setAllowedRewardMintAmount(type(uint104).max);

        IL1RewardManager.MintAndBridgeParams memory params = IL1RewardManager.MintAndBridgeParams({
            bridge: bridge,
            rewardsAmount: 1 ether,
            startEpoch: 1,
            endEpoch: 10,
            rewardsRoot: bytes32("1"),
            rewardsURI: "uri"
        });

        l1RewardManager.mintAndBridgeRewards(params);
    }
}
