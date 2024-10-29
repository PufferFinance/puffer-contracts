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
import { IPufferRevenueDepositor } from "./interface/IPufferRevenueDepositor.sol";
import { InvalidAddress } from "./Errors.sol";

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

    /**
     * @notice The maximum rewards distribution window.
     */
    uint256 private constant _MAXIMUM_DISTRIBUTION_WINDOW = 7 days;

    /**
     * @notice The basis point scale. (10000 bps = 100%)
     */
    uint256 private constant _BASIS_POINT_SCALE = 10000;

    /**
     * @notice The maximum rewards in basis points. (10% is the max rewards amount for treasury and RNO)
     */
    uint256 private constant _MAX_REWARDS_BPS = 1000;

    /**
     * @notice PufferVault contract.
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    PufferVaultV4 public immutable PUFFER_VAULT;

    /**
     * @notice WETH contract.
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IWETH public immutable WETH;

    /**
     * @notice Treasury contract.
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    address public immutable TREASURY;

    /**
     * @param vault PufferVault contract
     * @param weth WETH contract
     * @param treasury Puffer Treasury contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address vault, address weth, address treasury) {
        PUFFER_VAULT = PufferVaultV4(payable(vault));
        WETH = IWETH(weth);
        TREASURY = treasury;
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract.
     * @param accessManager The address of the access manager.
     * @param operatorsAddresses The addresses of the restaking operators.
     */
    function initialize(address accessManager, address[] calldata operatorsAddresses) external initializer {
        __AccessManaged_init(accessManager);
        _addRestakingOperators(operatorsAddresses);
        _setTreasuryRewardsBps(500); // 5%
        _setRnoRewardsBps(400); // 4%
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

        return $.lastDepositAmount * remainingTime / rewardsDistributionWindow;
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
        require(getPendingDistributionAmount() == 0, VaultHasUndepositedRewards());

        RevenueDepositorStorage storage $ = _getRevenueDepositorStorage();
        $.lastDepositTimestamp = uint48(block.timestamp);

        // Wrap any ETH sent to the contract
        if (address(this).balance > 0) {
            WETH.deposit{ value: address(this).balance }();
        }
        // nosemgrep tin-reentrant-dbl-diff-balance
        uint256 rewardsAmount = WETH.balanceOf(address(this));

        uint256 treasuryRewards = (rewardsAmount * $.treasuryRewardsBps) / _BASIS_POINT_SCALE;

        require(treasuryRewards > 0, NothingToDistribute());
        WETH.transfer(TREASURY, treasuryRewards);

        uint256 rnoRewards = (rewardsAmount * $.rNORewardsBps) / _BASIS_POINT_SCALE;

        // Distribute RNO rewards using push pattern because it is WETH and more convenient
        uint256 operatorCount = $.restakingOperators.length();
        uint256 rewardPerOperator = rnoRewards / operatorCount;

        for (uint256 i = 0; i < operatorCount; ++i) {
            WETH.transfer($.restakingOperators.at(i), rewardPerOperator);
        }

        // Deposit remaining rewards to the PufferVault
        uint256 vaultRewards = WETH.balanceOf(address(this));
        $.lastDepositAmount = uint104(vaultRewards);
        WETH.transfer(address(PUFFER_VAULT), vaultRewards);

        emit RevenueDeposited(vaultRewards);
    }

    /**
     * @notice Returns the last deposit timestamp.
     * @return The last deposit timestamp in seconds.
     */
    function getLastDepositTimestamp() public view returns (uint256) {
        return _getRevenueDepositorStorage().lastDepositTimestamp;
    }

    /**
     * @notice Get restaking operators.
     * @return The addresses of the restaking operators.
     */
    function getRestakingOperators() external view returns (address[] memory) {
        return _getRevenueDepositorStorage().restakingOperators.values();
    }

    /**
     * @notice Get the RNO rewards basis points.
     * @return The RNO rewards in basis points.
     */
    function getRnoRewardsBps() external view returns (uint128) {
        return _getRevenueDepositorStorage().rNORewardsBps;
    }

    /**
     * @notice Get the treasury rewards basis points.
     * @return The RNO rewards in basis points.
     */
    function getTreasuryRewardsBps() external view returns (uint128) {
        return _getRevenueDepositorStorage().treasuryRewardsBps;
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
     * @notice Set the RNO rewards basis points.
     * @dev Restricted access to `ROLE_ID_DAO`
     * @param newBps The new RNO rewards in basis points.
     */
    function setRnoRewardsBps(uint128 newBps) external restricted {
        _setRnoRewardsBps(newBps);
    }

    function _setRnoRewardsBps(uint128 newBps) internal {
        require(newBps <= _MAX_REWARDS_BPS, InvalidBps());

        RevenueDepositorStorage storage $ = _getRevenueDepositorStorage();

        emit RnoRewardsBpsChanged($.rNORewardsBps, newBps);
        $.rNORewardsBps = newBps;
    }

    /**
     * @notice Set the treasury rewards basis points.
     * @dev Restricted access to `ROLE_ID_DAO`
     * @param newBps The new treasury rewards in basis points.
     */
    function setTreasuryRewardsBps(uint128 newBps) external restricted {
        _setTreasuryRewardsBps(newBps);
    }

    function _setTreasuryRewardsBps(uint128 newBps) internal {
        require(newBps <= _MAX_REWARDS_BPS, InvalidBps());

        RevenueDepositorStorage storage $ = _getRevenueDepositorStorage();

        emit TreasuryRewardsBpsChanged($.treasuryRewardsBps, newBps);
        $.treasuryRewardsBps = newBps;
    }

    /**
     * @notice Remove restaking operator.
     * @dev Restricted access to `ROLE_ID_OPERATIONS_MULTISIG`
     * @param operatorAddress The address of the restaking operator.
     */
    function removeRestakingOperator(address operatorAddress) external restricted {
        RevenueDepositorStorage storage $ = _getRevenueDepositorStorage();

        bool success = $.restakingOperators.remove(operatorAddress);
        require(success, RestakingOperatorNotSet());
        emit RestakingOperatorRemoved(operatorAddress);
    }

    /**
     * @notice Add new restaking operators.
     * @dev Restricted access to `ROLE_ID_OPERATIONS_MULTISIG`
     * @param operatorsAddresses The addresses of the restaking operators.
     */
    function addRestakingOperators(address[] calldata operatorsAddresses) external restricted {
        _addRestakingOperators(operatorsAddresses);
    }

    function _addRestakingOperators(address[] calldata operatorsAddresses) internal {
        RevenueDepositorStorage storage $ = _getRevenueDepositorStorage();

        for (uint256 i = 0; i < operatorsAddresses.length; ++i) {
            require(operatorsAddresses[i] != address(0), InvalidAddress());
            bool success = $.restakingOperators.add(operatorsAddresses[i]);
            require(success, RestakingOperatorAlreadySet());
            emit RestakingOperatorAdded(operatorsAddresses[i]);
        }
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    // slither-disable-next-line dead-code
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
