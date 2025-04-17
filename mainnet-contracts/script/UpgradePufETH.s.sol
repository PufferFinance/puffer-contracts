// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { stdJson } from "forge-std/StdJson.sol";
import { BaseScript } from ".//BaseScript.s.sol";
import { PufferVaultV5 } from "../src/PufferVaultV5.sol";
import { PufferVaultV2 } from "../src/PufferVaultV2.sol";
import { PufferVaultV5Tests } from "../test/mocks/PufferVaultV5Tests.sol";
import { IEigenLayer } from "../src/interface/Eigenlayer-Slashing/IEigenLayer.sol";
import { IStrategy } from "../src/interface/Eigenlayer-Slashing/IStrategy.sol";
import { IDelegationManager } from "../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IStETH } from "../src/interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "../src/interface/Lido/ILidoWithdrawalQueue.sol";
import { LidoWithdrawalQueueMock } from "../test/mocks/LidoWithdrawalQueueMock.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IWETH } from "../src/interface/Other/IWETH.sol";
import { IPufferOracleV2 } from "../src/interface/IPufferOracleV2.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PufferDeployment } from "../src/structs/PufferDeployment.sol";
import { BridgingDeployment } from "./DeploymentStructs.sol";
import { IPufferRevenueDepositor } from "../src/interface/IPufferRevenueDepositor.sol";
import { IPufferOracle } from "../src/interface/IPufferOracle.sol";

/**
 * @title UpgradePufETH
 * @author Puffer Finance
 * @notice Upgrades PufETH
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
 *         PK=${deployer_pk} forge script script/UpgradePufETH.s.sol:UpgradePufETH --sig 'run(address)' "VAULTADDRESS" -vvvv --rpc-url=... --broadcast
 */
contract UpgradePufETH is BaseScript {
    /**
     * @dev Ethereum Mainnet addresses
     */
    IStrategy internal constant _EIGEN_STETH_STRATEGY = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
    IEigenLayer internal constant _EIGEN_STRATEGY_MANAGER = IEigenLayer(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);
    IDelegationManager internal constant _DELEGATION_MANAGER =
        IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    IStETH internal constant _ST_ETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWETH internal constant _WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ILidoWithdrawalQueue internal constant _LIDO_WITHDRAWAL_QUEUE =
        ILidoWithdrawalQueue(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

    function run(PufferDeployment memory deployment, address pufferOracle, address revenueDepositor) public broadcast {
        //@todo this is for tests only
        AccessManager(deployment.accessManager).grantRole(1, _broadcaster, 0);

        PufferVaultV2 newImplementationV2 = new PufferVaultV2(
            IStETH(deployment.stETH),
            IWETH(deployment.weth),
            ILidoWithdrawalQueue(deployment.lidoWithdrawalQueueMock),
            IPufferOracle(pufferOracle)
        );

        // It is necessary to upgrade to VaultV2 because in that upgrade we changed the underlying asset from stETH to WETH
        // Initialize VaultV2 to swap stETH for WETH as the asset
        UUPSUpgradeable(deployment.pufferVault).upgradeToAndCall(
            address(newImplementationV2), abi.encodeCall(PufferVaultV2.initialize, ())
        );

        PufferVaultV5 newImplementation = new PufferVaultV5Tests(
            IStETH(deployment.stETH),
            IWETH(deployment.weth),
            ILidoWithdrawalQueue(deployment.lidoWithdrawalQueueMock),
            IPufferOracleV2(pufferOracle),
            IPufferRevenueDepositor(revenueDepositor)
        );

        vm.label(address(newImplementation), "PufferVaultV5Implementation");

        UUPSUpgradeable(deployment.pufferVault).upgradeToAndCall(address(newImplementation), "");
    }
}
