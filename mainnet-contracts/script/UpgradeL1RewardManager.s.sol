// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { L1RewardManager } from "../src/L1RewardManager.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { GenerateRewardManagerCalldata } from "./AccessManagerMigrations/03_GenerateRewardManagerCalldata.s.sol";

/**
 * @notice Upgrades the L1RewardManager from the LayerZero bridging version to the version where the rewards are claimed on L1
 * @dev
 * To run the simulation do the following:
 *         REWARD_WATCHER=<watcher address> forge script script/UpgradeL1RewardManager.s.sol:UpgradeL1RewardManager -vvvv --rpc-url=...
 *
 * If everything looks good, run the same command with `--broadcast --verify`
 *
 * The script deploys the implementation and prints two Timelock transactions:
 * 1. AccessManager multicall: maps the new functions, closes the bridging functions and revokes `ROLE_ID_BRIDGE`
 * 2. upgradeToAndCall on the L1RewardManager proxy, with `initializeV2`
 * Execute them in this order, one right after the other.
 *
 * Before the execution:
 * - Put the L2RewardManager on Base in claim-only mode (script/SetL2RewardManagerClaimOnly.s.sol)
 * - Check that no interval is frozen on Base
 * - Check that the last interval that was bridged to Base is past its claiming delay
 */
contract UpgradeL1RewardManager is DeployerHelper {
    /**
     * @notice The claiming delay for new intervals
     */
    uint256 internal constant CLAIMING_DELAY = 24 hours;

    /**
     * @notice The minimum time between two mints
     */
    uint104 internal constant MINT_FREQUENCY = 72 hours;

    bytes public upgradeCallData;
    bytes public accessManagerCallData;

    function run() public {
        run(vm.envOr("REWARD_WATCHER", address(0)));
    }

    /**
     * @param rewardWatcher The account that gets `ROLE_ID_REWARD_WATCHER`. Use address(0) to skip the grant
     */
    function run(address rewardWatcher) public {
        address l1RewardManagerProxy = _getL1RewardManager();

        GenerateRewardManagerCalldata calldataGenerator = new GenerateRewardManagerCalldata();

        vm.startBroadcast();
        _getDeployer();

        L1RewardManager l1RewardManagerImpl = new L1RewardManager(_getPufferVault());
        vm.label(address(l1RewardManagerImpl), "l1RewardManagerImpl");

        vm.stopBroadcast();

        accessManagerCallData =
            calldataGenerator.generateL1Calldata(l1RewardManagerProxy, rewardWatcher, _getL1BridgeRoleHolders());

        upgradeCallData = abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall,
            (
                address(l1RewardManagerImpl),
                abi.encodeCall(L1RewardManager.initializeV2, (CLAIMING_DELAY, MINT_FREQUENCY, _getPufETHOFTAdapter()))
            )
        );

        if (rewardWatcher == address(0)) {
            console.log("WARNING: REWARD_WATCHER is not set, ROLE_ID_REWARD_WATCHER is not granted");
        }

        console.log("1. Queue from Timelock -> AccessManager", _getAccessManager());
        console.logBytes(accessManagerCallData);
        console.log("================================================");
        console.log("2. Queue from Timelock -> l1RewardManagerProxy", l1RewardManagerProxy);
        console.logBytes(upgradeCallData);
    }

    /**
     * @dev The accounts that hold `ROLE_ID_BRIDGE` on Mainnet (checked on 2026-09-25).
     * The role is only used by the bridging functions of the L1RewardManager.
     */
    function _getL1BridgeRoleHolders() internal pure returns (address[] memory holders) {
        holders = new address[](3);
        // Connext, from the first bridging version
        holders[0] = 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6;
        // Operations Multisig, used to process a revert by hand in 2025
        holders[1] = 0xC0896ab1A8cae8c2C1d27d011eb955Cca955580d;
        // LayerZero V2 endpoint
        holders[2] = 0x1a44076050125825900e736c501f859c50fE728c;
    }
}
