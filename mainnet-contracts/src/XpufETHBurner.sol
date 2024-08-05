// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IXReceiver } from "@connext/interfaces/core/IXReceiver.sol";
import { IXERC20Lockbox } from "./interface/IXERC20Lockbox.sol";
import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Unauthorized } from "mainnet-contracts/src/Errors.sol";
import { L2RewardManagerStorage } from "l2-contracts/src/L2RewardManagerStorage.sol";

/**
 * @title XPufETHBurner
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract XPufETHBurner is IXReceiver, AccessManagedUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @notice The XPUFETH token contract on Ethereum Mainnet
     */
    IERC20 public immutable XPUFETH;
    /**
     * @notice The PufferVault contract on Ethereum Mainnet
     */
    PufferVaultV3 public immutable pufETH;
    /**
     * @notice The XERC20Lockbox contract on Ethereum Mainnet
     */
    IXERC20Lockbox public immutable LOCKBOX;
    /**
     * @notice The Rewards Manager contract on L2
     */
    address public immutable L2_REWARDS_MANAGER;

    constructor(address XpufETH, address lockbox, address l2RewardsManager) {
        XPUFETH = IERC20(XpufETH);
        LOCKBOX = IXERC20Lockbox(lockbox);
        L2_REWARDS_MANAGER = l2RewardsManager;
        _disableInitializers();
    }

    modifier onlyRewardsManager(address originSender) {
        if (originSender != address(L2_REWARDS_MANAGER)) {
            revert Unauthorized();
        }
        _;
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
    }

    /**
     * @notice This contract receives XPufETH from the L2 via bridge, unwraps it to pufETH and then burns the pufETH, reverting the original mintAndBridge call
     */
    function xReceive(bytes32, uint256, address, address originSender, uint32, bytes memory callData)
        external
        override(IXReceiver)
        onlyRewardsManager(originSender)
        restricted
        returns (bytes memory)
    {
        // We decode the data to get the amount of shares and the ETH amount
        L2RewardManagerStorage.EpochRecord memory epochRecord =
            abi.decode(callData, (L2RewardManagerStorage.EpochRecord));

        XPUFETH.safeIncreaseAllowance(address(LOCKBOX), epochRecord.pufETHAmount);
        // get the pufETH
        LOCKBOX.withdraw(epochRecord.pufETHAmount);

        // Tell the PufferVault to burn the pufETH and subtract from the ethRewardsAmount
        // The PufferVault will subtract ethAmount from the rewardsAmount and burn the pufETH from this contract
        pufETH.revertBridgingInterval({
            pufETHAmount: epochRecord.pufETHAmount,
            ethAmount: epochRecord.ethAmount,
            startEpoch: epochRecord.startEpoch,
            endEpoch: epochRecord.endEpoch,
            rewardsRoot: epochRecord.rewardRoot
        });

        return "";
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
