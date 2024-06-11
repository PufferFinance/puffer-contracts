// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import { IXERC20 } from "../interface/IXERC20.sol";
import { IOptimismMintableERC20 } from "../interface/IOptimismMintableERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { xPufETHStorage } from "./xPufETHStorage.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title xPufETH
 * @author Puffer Finance
 * @dev It is an XERC20 implementation of pufETH token. This token is to be deployed to L2 chains.
 * @custom:security-contact security@puffer.fi
 */
contract xPufETH is
    xPufETHStorage,
    IXERC20,
    AccessManagedUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable,
    IOptimismMintableERC20
{
    /**
     * @notice The duration it takes for the limits to fully replenish
     */
    uint256 private constant _DURATION = 1 days;

    /**
     * @notice These two params are only needed for L2 tokens that use OptimismMintableERC20 bridges
     */
    address public immutable remoteToken;
    address public immutable bridge;

    constructor(address opRemoteToken, address opBridge) {
        _disableInitializers();
        remoteToken = opRemoteToken;
        bridge = opBridge;
    }

    function initialize(address accessManager) public initializer {
        __AccessManaged_init(accessManager);
        __ERC20_init("xPufETH", "xPufETH");
        __ERC20Permit_init("xPufETH");
    }

    /**
     * @notice Mints tokens for a user
     * @dev Can only be called by a bridge
     * @param user The address of the user who needs tokens minted
     * @param amount The amount of tokens being minted
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function mint(address user, uint256 amount) external override(IXERC20, IOptimismMintableERC20) restricted {
        _mintWithCaller(msg.sender, user, amount);
    }

    /**
     * @notice Burns tokens for a user
     * @dev Can only be called by a bridge
     * @param user The address of the user who needs tokens burned
     * @param amount The amount of tokens being burned
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function burn(address user, uint256 amount) external override(IXERC20, IOptimismMintableERC20) restricted {
        if (msg.sender != user) {
            _spendAllowance(user, msg.sender, amount);
        }

        _burnWithCaller(msg.sender, user, amount);
    }

    /**
     * @notice Sets the lockbox address
     *
     * @dev Restricted to the DAO
     * @param lockboxAddress The address of the lockbox
     */
    function setLockbox(address lockboxAddress) external restricted {
        xPufETH storage $ = _getXPufETHStorage();
        $.lockbox = lockboxAddress;

        emit LockboxSet(lockboxAddress);
    }

    /**
     * @notice Updates the limits of any bridge
     *
     * @dev Restricted to the DAO
     * @param mintingLimit The updated minting limit we are setting to the bridge
     * @param burningLimit The updated burning limit we are setting to the bridge
     * @param targetBridge The address of the bridge we are setting the limits too
     */
    function setLimits(address targetBridge, uint256 mintingLimit, uint256 burningLimit) external restricted {
        if (mintingLimit > (type(uint256).max / 2) || burningLimit > (type(uint256).max / 2)) {
            revert IXERC20_LimitsTooHigh();
        }

        _changeMinterLimit(targetBridge, mintingLimit);
        _changeBurnerLimit(targetBridge, burningLimit);
        emit BridgeLimitsSet(mintingLimit, burningLimit, targetBridge);
    }

    /**
     * @notice Returns the max limit of a bridge
     *
     * @param targetBridge the bridge we are viewing the limits of
     * @return limit The limit the targetBridge has
     */
    function mintingMaxLimitOf(address targetBridge) public view returns (uint256 limit) {
        xPufETH storage $ = _getXPufETHStorage();
        limit = $.bridges[targetBridge].minterParams.maxLimit;
    }

    /**
     * @notice Returns the max limit of a bridge
     *
     * @param targetBridge the bridge we are viewing the limits of
     * @return limit The limit the targetBridge has
     */
    function burningMaxLimitOf(address targetBridge) public view returns (uint256 limit) {
        xPufETH storage $ = _getXPufETHStorage();
        limit = $.bridges[targetBridge].burnerParams.maxLimit;
    }

    /**
     * @notice Returns the current limit of a bridge
     *
     * @param targetBridge the bridge we are viewing the limits of
     * @return limit The limit the bridge has
     */
    function mintingCurrentLimitOf(address targetBridge) public view returns (uint256 limit) {
        xPufETH storage $ = _getXPufETHStorage();
        limit = _getCurrentLimit(
            $.bridges[targetBridge].minterParams.currentLimit,
            $.bridges[targetBridge].minterParams.maxLimit,
            $.bridges[targetBridge].minterParams.timestamp,
            $.bridges[targetBridge].minterParams.ratePerSecond
        );
    }

    /**
     * @notice Returns the current limit of a bridge
     *
     * @param targetBridge the bridge we are viewing the limits of
     * @return limit The limit the bridge has
     */
    function burningCurrentLimitOf(address targetBridge) public view returns (uint256 limit) {
        xPufETH storage $ = _getXPufETHStorage();
        limit = _getCurrentLimit(
            $.bridges[targetBridge].burnerParams.currentLimit,
            $.bridges[targetBridge].burnerParams.maxLimit,
            $.bridges[targetBridge].burnerParams.timestamp,
            $.bridges[targetBridge].burnerParams.ratePerSecond
        );
    }

    /**
     * @notice Uses the limit of any bridge
     * @param targetBridge The address of the bridge who is being changed
     * @param change The change in the limit
     */
    function _useMinterLimits(address targetBridge, uint256 change) internal {
        xPufETH storage $ = _getXPufETHStorage();
        uint256 currentLimit = mintingCurrentLimitOf(targetBridge);
        $.bridges[targetBridge].minterParams.timestamp = block.timestamp;
        $.bridges[targetBridge].minterParams.currentLimit = currentLimit - change;
    }

    /**
     * @notice Uses the limit of any bridge
     * @param targetBridge The address of the bridge who is being changed
     * @param change The change in the limit
     */
    function _useBurnerLimits(address targetBridge, uint256 change) internal {
        xPufETH storage $ = _getXPufETHStorage();
        uint256 currentLimit = burningCurrentLimitOf(targetBridge);
        $.bridges[targetBridge].burnerParams.timestamp = block.timestamp;
        $.bridges[targetBridge].burnerParams.currentLimit = currentLimit - change;
    }

    /**
     * @notice Updates the limit of any bridge
     * @dev Can only be called by the owner
     * @param targetBridge The address of the bridge we are setting the limit too
     * @param limit The updated limit we are setting to the bridge
     */
    function _changeMinterLimit(address targetBridge, uint256 limit) internal {
        xPufETH storage $ = _getXPufETHStorage();
        uint256 oldLimit = $.bridges[targetBridge].minterParams.maxLimit;
        uint256 currentLimit = mintingCurrentLimitOf(targetBridge);
        $.bridges[targetBridge].minterParams.maxLimit = limit;

        $.bridges[targetBridge].minterParams.currentLimit = _calculateNewCurrentLimit(limit, oldLimit, currentLimit);

        $.bridges[targetBridge].minterParams.ratePerSecond = limit / _DURATION;
        $.bridges[targetBridge].minterParams.timestamp = block.timestamp;
    }

    /**
     * @notice Updates the limit of any bridge
     * @dev Can only be called by the owner
     * @param targetBridge The address of the bridge we are setting the limit too
     * @param limit The updated limit we are setting to the bridge
     */
    function _changeBurnerLimit(address targetBridge, uint256 limit) internal {
        xPufETH storage $ = _getXPufETHStorage();
        uint256 oldLimit = $.bridges[targetBridge].burnerParams.maxLimit;
        uint256 currentLimit = burningCurrentLimitOf(targetBridge);
        $.bridges[targetBridge].burnerParams.maxLimit = limit;

        $.bridges[targetBridge].burnerParams.currentLimit = _calculateNewCurrentLimit(limit, oldLimit, currentLimit);

        $.bridges[targetBridge].burnerParams.ratePerSecond = limit / _DURATION;
        $.bridges[targetBridge].burnerParams.timestamp = block.timestamp;
    }

    /**
     * @notice Updates the current limit
     *
     * @param limit The new limit
     * @param oldLimit The old limit
     * @param currentLimit The current limit
     * @return newCurrentLimit The new current limit
     */
    function _calculateNewCurrentLimit(uint256 limit, uint256 oldLimit, uint256 currentLimit)
        internal
        pure
        returns (uint256 newCurrentLimit)
    {
        uint256 difference;

        if (oldLimit > limit) {
            difference = oldLimit - limit;
            newCurrentLimit = currentLimit > difference ? currentLimit - difference : 0;
        } else {
            difference = limit - oldLimit;
            newCurrentLimit = currentLimit + difference;
        }
    }

    /**
     * @notice Gets the current limit
     *
     * @param currentLimit The current limit
     * @param maxLimit The max limit
     * @param timestamp The timestamp of the last update
     * @param ratePerSecond The rate per second
     * @return limit The current limit
     */
    function _getCurrentLimit(uint256 currentLimit, uint256 maxLimit, uint256 timestamp, uint256 ratePerSecond)
        internal
        view
        returns (uint256 limit)
    {
        limit = currentLimit;
        if (limit == maxLimit) {
            return limit;
        } else if (timestamp + _DURATION <= block.timestamp) {
            limit = maxLimit;
        } else if (timestamp + _DURATION > block.timestamp) {
            uint256 _timePassed = block.timestamp - timestamp;
            uint256 _calculatedLimit = limit + (_timePassed * ratePerSecond);
            limit = _calculatedLimit > maxLimit ? maxLimit : _calculatedLimit;
        }
    }

    /**
     * @notice Internal function for burning tokens
     *
     * @param caller The caller address
     * @param user The user address
     * @param amount The amount to burn
     */
    function _burnWithCaller(address caller, address user, uint256 amount) internal {
        xPufETH storage $ = _getXPufETHStorage();
        if (caller != $.lockbox) {
            uint256 currentLimit = burningCurrentLimitOf(caller);
            if (currentLimit < amount) revert IXERC20_NotHighEnoughLimits();
            _useBurnerLimits(caller, amount);
        }
        _burn(user, amount);
    }

    /**
     * @notice Internal function for minting tokens
     *
     * @param caller The caller address
     * @param user The user address
     * @param amount The amount to mint
     */
    function _mintWithCaller(address caller, address user, uint256 amount) internal {
        xPufETH storage $ = _getXPufETHStorage();
        if (caller != $.lockbox) {
            uint256 currentLimit = mintingCurrentLimitOf(caller);
            if (currentLimit < amount) revert IXERC20_NotHighEnoughLimits();
            _useMinterLimits(caller, amount);
        }
        _mint(user, amount);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    // slither-disable-next-line dead-code
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }

    /**
     * @dev Returns true for the supported interface ids
     * @param interfaceId the given interface id
     */
    function supportsInterface(bytes4 interfaceId) public pure override(IERC165) returns (bool) {
        return interfaceId == type(IOptimismMintableERC20).interfaceId;
    }
}
