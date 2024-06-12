// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.4 <0.9.0;

interface IXERC20 {
    /**
     * @notice Emits when a lockbox is set
     *
     * @param lockbox The address of the lockbox
     */
    event LockboxSet(address lockbox);

    /**
     * @notice Emits when a limit is set
     *
     * @param mintingLimit The updated minting limit we are setting to the bridge
     * @param burningLimit The updated burning limit we are setting to the bridge
     * @param bridge The address of the bridge we are setting the limit too
     */
    event BridgeLimitsSet(uint256 mintingLimit, uint256 burningLimit, address indexed bridge);

    /**
     * @notice Reverts when a user with too low of a limit tries to call mint/burn
     */
    error IXERC20_NotHighEnoughLimits();

    /**
     * @notice Reverts when caller is not the factory
     */
    error IXERC20_NotFactory();

    /**
     * @notice Reverts when limits are too high
     */
    error IXERC20_LimitsTooHigh();

    /**
     * @notice Contains the full minting and burning data for a particular bridge
     *
     * @param minterParams The minting parameters for the bridge
     * @param burnerParams The burning parameters for the bridge
     */
    struct Bridge {
        BridgeParameters minterParams;
        BridgeParameters burnerParams;
    }

    /**
     * @notice Contains the mint or burn parameters for a bridge
     *
     * @param timestamp The timestamp of the last mint/burn
     * @param ratePerSecond The rate per second of the bridge
     * @param maxLimit The max limit of the bridge
     * @param currentLimit The current limit of the bridge
     */
    struct BridgeParameters {
        uint256 timestamp;
        uint256 ratePerSecond;
        uint256 maxLimit;
        uint256 currentLimit;
    }

    /**
     * @notice Sets the lockbox address
     *
     * @param lockbox The address of the lockbox
     */
    function setLockbox(address lockbox) external;

    /**
     * @notice Updates the limits of any bridge
     * @dev Can only be called by the owner
     * @param mintingLimit The updated minting limit we are setting to the bridge
     * @param burningLimit The updated burning limit we are setting to the bridge
     * @param bridge The address of the bridge we are setting the limits too
     */
    function setLimits(address bridge, uint256 mintingLimit, uint256 burningLimit) external;

    /**
     * @notice Returns the max limit of a minter
     *
     * @param minter The minter we are viewing the limits of
     *  @return limit The limit the minter has
     */
    function mintingMaxLimitOf(address minter) external view returns (uint256 limit);

    /**
     * @notice Returns the max limit of a bridge
     *
     * @param bridge the bridge we are viewing the limits of
     * @return limit The limit the bridge has
     */
    function burningMaxLimitOf(address bridge) external view returns (uint256 limit);

    /**
     * @notice Returns the current limit of a minter
     *
     * @param minter The minter we are viewing the limits of
     * @return limit The limit the minter has
     */
    function mintingCurrentLimitOf(address minter) external view returns (uint256 limit);

    /**
     * @notice Returns the current limit of a bridge
     *
     * @param bridge the bridge we are viewing the limits of
     * @return limit The limit the bridge has
     */
    function burningCurrentLimitOf(address bridge) external view returns (uint256 limit);

    /**
     * @notice Mints tokens for a user
     * @dev Can only be called by a minter
     * @param user The address of the user who needs tokens minted
     * @param amount The amount of tokens being minted
     */
    function mint(address user, uint256 amount) external;

    /**
     * @notice Burns tokens for a user
     * @dev Can only be called by a minter
     * @param user The address of the user who needs tokens burned
     * @param amount The amount of tokens being burned
     */
    function burn(address user, uint256 amount) external;
}
