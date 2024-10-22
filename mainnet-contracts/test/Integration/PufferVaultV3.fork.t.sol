// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC4626Upgradeable } from "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { IPufferVaultV3 } from "../../src/interface/IPufferVaultV3.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ROLE_ID_DAO, ROLE_ID_PUFFER_PROTOCOL } from "../../script/Roles.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract PufferVaultV4ForkTest is MainnetForkTestHelper {
    function setUp() public virtual override {
        // Cancun upgrade
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21019835); // (Oct-22-2024 08:09:59 AM +UTC)

        // Setup contracts that are deployed to mainnet
        _setupLiveContracts();

        // Upgrade to latest version
        _upgradeToMainnetV4Puffer();

        // vm.startPrank(OPERATIONS_MULTISIG);
        // xpufETH.setLockbox(address(lockBox));
        // xpufETH.setLimits(address(connext), 1000 ether, 1000 ether);
        // pufferVault.setAllowedRewardMintFrequency(1 days);
        // IPufferVaultV3.BridgeData memory bridgeData = IPufferVaultV3.BridgeData({ destinationDomainId: 1 });

        // pufferVault.updateBridgeData(address(connext), bridgeData);
    }

    // Sanity check
    // function test_sanity() public view {
    //     assertEq(pufferVault.name(), "pufETH", "name");
    //     assertEq(pufferVault.symbol(), "pufETH", "symbol");
    //     assertEq(pufferVault.decimals(), 18, "decimals");
    //     assertEq(pufferVault.asset(), address(_WETH), "asset");
    //     assertEq(pufferVault.getTotalRewardMintAmount(), 0, "0 rewards");
    // }

    // function test_mintAndBridge() public {
    //     // first updateBridgeData

    //     // IPufferVaultV3.MintAndBridgeParams memory params = IPufferVaultV3.MintAndBridgeParams({
    //     //     bridge: address(connext),
    //     //     rewardsAmount: 100 ether,
    //     //     startEpoch: 1,
    //     //     endEpoch: 2,
    //     //     rewardsRoot: bytes32(0),
    //     //     rewardsURI: "uri"
    //     // });

    //     uint256 initialTotalAssets = pufferVault.totalAssets();

    //     // vm.startPrank(DAO);

    //     // pufferVault.setAllowedRewardMintAmount(100 ether);
    //     // pufferVault.mintAndBridgeRewards{ value: 1 ether }(params);

    //     assertEq(pufferVault.totalAssets(), initialTotalAssets + 100 ether);
    // }
}
