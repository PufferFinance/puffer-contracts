// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultV4 } from "./PufferVaultV4.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IWETH } from "./interface/Other/IWETH.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PufferRevenueDepositorStorage } from "./PufferRevenueDepositorStorage.sol";
import { IAeraVault, AssetValue } from "./interface/Other/IAeraVault.sol";
import { IPufferRevenueDepositor } from "./interface/IPufferRevenueDepositor.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PufferRevenueDepositor
 * @notice This contract is used to "slowly" deposit revenue into PufferVault.
 * @dev The funds are deposited immediately but the exchange rate change doesn't happen until the rewards distribution window is over.
 * @custom:security-contact security@puffer.fi
 */
contract PufferRevenueDepositor is
    IPufferRevenueDepositor,
    PufferRevenueDepositorStorage,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;

    /**
     * @notice The maximum rewards distribution window.
     */
    uint256 private constant _MAXIMUM_DISTRIBUTION_WINDOW = 7 days;

    /**
     * @notice PufferVault contract.
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    PufferVaultV4 public immutable PUFFER_VAULT;

    /**
     * @notice AeraVault contract.
     */
    IAeraVault public immutable AERA_VAULT;

    /**
     * @notice WETH contract.
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IWETH public immutable WETH;

    /**
     * @param vault PufferVault contract
     * @param weth WETH contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address vault, address weth, address aeraVault) {
        if (vault == address(0) || weth == address(0) || aeraVault == address(0)) {
            revert InvalidAddress();
        }
        PUFFER_VAULT = PufferVaultV4(payable(vault));
        AERA_VAULT = IAeraVault(aeraVault);
        WETH = IWETH(weth);
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract.
     * @param accessManager The address of the access manager.
     */
    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
    }

    /**
     * @notice Can receive ETH
     */
    receive() external payable { }

    /**
     * @inheritdoc IPufferRevenueDepositor
     */
    function getPendingDistributionAmount() public view returns (uint256) {
        RevenueDepositorStorage storage $ = _getRevenueDepositorStorage();

        uint256 rewardsDistributionWindow = $.rewardsDistributionWindow;

        // If the rewards distribution window is not set, return 0 to avoid division by 0
        // This also means that the deposits are instant
        if (rewardsDistributionWindow == 0) {
            return 0;
        }

        uint256 timePassed = block.timestamp - $.lastDepositTimestamp;
        uint256 remainingTime = rewardsDistributionWindow - Math.min(timePassed, rewardsDistributionWindow);

        return Math.mulDiv(uint256($.lastDepositAmount), remainingTime, rewardsDistributionWindow, Math.Rounding.Ceil);
    }

    /**
     * @inheritdoc IPufferRevenueDepositor
     */
    function getRewardsDistributionWindow() public view returns (uint256) {
        return _getRevenueDepositorStorage().rewardsDistributionWindow;
    }

    /**
     * @notice Deposit revenue into PufferVault.
     * @dev Restricted access to `ROLE_ID_REVENUE_DEPOSITOR`
     */
    function depositRevenue() external restricted {
        _depositRevenue();
    }

    /**
     * @notice Returns the last deposit timestamp.
     * @return The last deposit timestamp in seconds.
     */
    function getLastDepositTimestamp() public view returns (uint256) {
        return _getRevenueDepositorStorage().lastDepositTimestamp;
    }

    /**
     * @notice Set the rewards distribution window.
     * @dev Restricted access to `ROLE_ID_DAO`
     * @param newRewardsDistributionWindow The new rewards distribution window in seconds.
     */
    function setRewardsDistributionWindow(uint24 newRewardsDistributionWindow) external restricted {
        require(getPendingDistributionAmount() == 0, CannotChangeDistributionWindow());
        require(newRewardsDistributionWindow <= _MAXIMUM_DISTRIBUTION_WINDOW, InvalidDistributionWindow());

        RevenueDepositorStorage storage $ = _getRevenueDepositorStorage();
        emit RewardsDistributionWindowChanged($.rewardsDistributionWindow, newRewardsDistributionWindow);
        $.rewardsDistributionWindow = newRewardsDistributionWindow;
    }

    /**
     * @notice Withdraw WETH from AeraVault and deposit into PufferVault.
     * @dev Restricted access to `ROLE_ID_REVENUE_DEPOSITOR`
     */
    function withdrawAndDeposit() external restricted {
        AssetValue[] memory assets = new AssetValue[](1);

        assets[0] = AssetValue({ asset: IERC20(address(WETH)), value: WETH.balanceOf(address(AERA_VAULT)) });

        // Withdraw WETH to this contract
        AERA_VAULT.withdraw(assets);

        _depositRevenue();
    }

    /**
     * @notice Call multiple targets with the given data.
     * @param targets The targets to call
     * @param data The data to call the targets with
     * @dev Restricted access to `ROLE_ID_OPERATIONS_MULTISIG`
     */
    function callTargets(address[] calldata targets, bytes[] calldata data) external restricted {
        if (targets.length != data.length || targets.length == 0) {
            revert InvalidDataLength();
        }

        for (uint256 i = 0; i < targets.length; ++i) {
            // nosemgrep arbitrary-low-level-call
            (bool success,) = targets[i].call(data[i]);
            require(success, TargetCallFailed());
        }
    }

    function _depositRevenue() internal {
        require(getPendingDistributionAmount() == 0, VaultHasUndepositedRewards());

        RevenueDepositorStorage storage $ = _getRevenueDepositorStorage();
        $.lastDepositTimestamp = uint48(block.timestamp);

        // Wrap any ETH sent to the contract
        if (address(this).balance > 0) {
            WETH.deposit{ value: address(this).balance }();
        }
        // nosemgrep tin-reentrant-dbl-diff-balance
        uint256 rewardsAmount = WETH.balanceOf(address(this));
        require(rewardsAmount > 0, NothingToDistribute());

        $.lastDepositAmount = uint104(rewardsAmount);
        WETH.transfer(address(PUFFER_VAULT), rewardsAmount);

        emit RevenueDeposited(rewardsAmount);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    // slither-disable-next-line dead-code
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
