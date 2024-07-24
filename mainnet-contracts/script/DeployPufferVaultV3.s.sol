// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { BaseScript } from ".//BaseScript.s.sol";
import { xPufETH } from "../src/l2/xPufETH.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { PufferVaultV2 } from "../src/PufferVaultV2.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {
    ROLE_ID_VT_PRICER,
    ROLE_ID_OPERATIONS_COORDINATOR,
    ROLE_ID_OPERATIONS_MULTISIG,
    ROLE_ID_DAO,
    PUBLIC_ROLE
} from "./Roles.sol";
import { IDelegationManager } from "../src/interface/EigenLayer/IDelegationManager.sol";

import { stETHStrategyTestnet } from "../test/mocks/stETHStrategyTestnet.sol";
import { PufferVault } from "../src/PufferVault.sol";
import { XERC20Lockbox } from "src/XERC20Lockbox.sol";
import { IEigenLayer } from "../src/interface/EigenLayer/IEigenLayer.sol";
import { IStrategy } from "../src/interface/EigenLayer/IStrategy.sol";
import { IStETH } from "../src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "../src/interface/Other/IWETH.sol";
import { WETH9 } from "../test/mocks/WETH9.sol";
import { IPufferOracle } from "../src/interface/IPufferOracle.sol";
import { PufferVaultV3 } from "../src/PufferVaultV3.sol";
import { PufferOracleV2 } from "../src/PufferOracleV2.sol";
import { IPufferVaultV3 } from "../src/interface/IPufferVaultV3.sol";
import { IGuardianModule } from "../src/interface/IGuardianModule.sol";
import { BridgeMock } from "../test/mocks/BridgeMock.sol";
import { L2RewardManager } from "../src/l2-contracts/L2RewardManager.sol";

/**
 * @title DeployPufferVaultV3
 * @author Puffer Finance
 * @notice Deploy XPufETH
 * @dev
 *
 *
 *         NOTE:
 *
 *         If you ran the deployment script, but did not `--broadcast` the transaction, it will still update your local chainId-deployment.json file.
 *         Other scripts will fail because addresses will be updated in deployments file, but the deployment never happened.
 *
 *         BaseScript.sol holds the private key logic, if you don't have `PK` ENV variable, it will use the default one PK from `makeAddr("pufferDeployer")`
 *
 *         PK=a990c824d7f6928806d93674ef4acd4b240ad60c9ce575777c87b36f9a3c32a8 forge script script/DeployPufferVaultV3.s.sol:DeployPufferVaultV3 -vvvv --rpc-url=https://holesky.gateway.tenderly.co/5ovlGAOeSvuI3UcQD2PoSD --broadcast
 */
contract DeployPufferVaultV3 is BaseScript {
    uint256 _MINTING_LIMIT = 1000 * 1e18;
    uint256 _BURNING_LIMIT = 1000 * 1e18;

    IDelegationManager internal constant _DELEGATION_MANAGER =
        IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    IStETH stETH;
    IWETH weth;
    ILidoWithdrawalQueue lidoWithdrawalQueue;
    IStrategy stETHStrategy;
    IEigenLayer eigenStrategyManager;

    PufferVault pufferVault;
    PufferVault pufferVaultImplementation;

    ERC1967Proxy vaultProxy;

    AccessManager accessManager;
    xPufETH xPufETHProxy;

    function run() public broadcast {
        stETH = IStETH(address(new WETH9()));
        weth = new WETH9();
        lidoWithdrawalQueue = ILidoWithdrawalQueue(address(0));
        eigenStrategyManager = IEigenLayer(address(0));

        accessManager = new AccessManager(_broadcaster);

        console.log("AccessManager", address(accessManager));

        stETHStrategyTestnet elStETHStrategy = new stETHStrategyTestnet();

        stETHStrategy = IStrategy(elStETHStrategy);
        address stETHAddress = address(stETH);

        // Deploy implementation contracts
        pufferVaultImplementation =
            new PufferVault(IStETH(stETHAddress), lidoWithdrawalQueue, stETHStrategy, eigenStrategyManager);

        vaultProxy = new ERC1967Proxy{ salt: bytes32("pufETH") }(
            address(pufferVaultImplementation), abi.encodeCall(xPufETH.initialize, (address(accessManager)))
        );

        BridgeMock bridge = new BridgeMock();

        xPufETH xpufETHImplementation = new xPufETH();

        xPufETHProxy = xPufETH(
            address(
                new ERC1967Proxy{ salt: bytes32("xPufETH") }(
                    address(xpufETHImplementation), abi.encodeCall(xPufETH.initialize, (address(accessManager)))
                )
            )
        );

        L2RewardManager l2RewardManager = new L2RewardManager(address(xPufETHProxy), address(vaultProxy));

        XERC20Lockbox xERC20Lockbox = new XERC20Lockbox({ xerc20: address(xPufETHProxy), erc20: address(vaultProxy) });

        IPufferVaultV3.BridgingConstructorParams memory bridgingParams = IPufferVaultV3.BridgingConstructorParams({
            xToken: address(xPufETHProxy),
            lockBox: address(xERC20Lockbox),
            l2RewardManager: address(l2RewardManager)
        });

        PufferOracleV2 oracle =
            new PufferOracleV2(IGuardianModule(address(0)), payable(address(vaultProxy)), address(accessManager));

        PufferVaultV3 newImplementation = new PufferVaultV3(
            IStETH(stETH),
            IWETH(weth),
            ILidoWithdrawalQueue(lidoWithdrawalQueue),
            IStrategy(elStETHStrategy),
            IEigenLayer(eigenStrategyManager),
            IPufferOracle(oracle),
            _DELEGATION_MANAGER,
            bridgingParams
        );

        UUPSUpgradeable(address(vaultProxy)).upgradeToAndCall(
            address(newImplementation), abi.encodeCall(PufferVaultV2.initialize, ())
        );

        IPufferVaultV3.BridgeData memory bridgeData = IPufferVaultV3.BridgeData({ destinationDomainId: 1 });

        PufferVaultV3(payable(address(vaultProxy))).updateBridgeData(address(bridge), bridgeData);

        PufferVaultV3(payable(address(vaultProxy))).setAllowedRewardMintAmount(1000 ether);

        console.log("PufferVault:", address(vaultProxy));
        console.log("xpufETHProxy:", address(xPufETHProxy));
        console.log("xpufETH implementation:", address(xpufETHImplementation));
        console.log("xERC20Lockbox:", address(xERC20Lockbox));
        console.log("L2RewardManager:", address(l2RewardManager));

        bytes memory data =
            abi.encodeWithSelector(xPufETH.setLimits.selector, address(bridge), _MINTING_LIMIT, _BURNING_LIMIT);

        accessManager.execute(address(xPufETHProxy), data);

        bytes memory setLockboxCalldata = abi.encodeCall(xPufETH.setLockbox, address(xERC20Lockbox));

        accessManager.execute(address(xPufETHProxy), setLockboxCalldata);

        setUpAccess();
    }

    function setUpAccess() internal {
        bytes4[] memory daoSelectors = new bytes4[](2);
        daoSelectors[0] = xPufETH.setLockbox.selector;
        daoSelectors[1] = xPufETH.setLimits.selector;

        bytes4[] memory publicSelectors = new bytes4[](2);
        publicSelectors[0] = xPufETH.mint.selector;
        publicSelectors[1] = xPufETH.burn.selector;

        // Setup Access
        // Public selectors
        accessManager.setTargetFunctionRole(address(xPufETHProxy), publicSelectors, accessManager.PUBLIC_ROLE());
        // Dao selectors
        accessManager.setTargetFunctionRole(address(xPufETHProxy), daoSelectors, ROLE_ID_DAO);
    }
}
