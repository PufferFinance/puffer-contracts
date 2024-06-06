// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IValidatorTicketPricer
 * @notice Interface for the ValidatorTicketPricer contract
 */
interface IValidatorTicketPricer {
    /**
     * @notice Thrown if the new value is invalid
     */
    error InvalidValue();

    /**
     * @notice Emitted when daily MEV payouts are updated
     * @param oldValue The old value of daily MEV payouts
     * @param newValue The new value of daily MEV payouts
     */
    event DailyMevPayoutsUpdated(uint104 oldValue, uint104 newValue);

    /**
     * @notice Emitted when daily consensus rewards are updated
     * @param oldValue The old value of daily consensus rewards
     * @param newValue The new value of daily consensus rewards
     */
    event DailyConsensusRewardsUpdated(uint104 oldValue, uint104 newValue);

    /**
     * @notice Emitted when daily MEV payouts change tolerance is updated
     * @param oldValue The old tolerance value
     * @param newValue The new tolerance value
     */
    event DailyMevPayoutsChangeToleranceBPSUpdated(uint16 oldValue, uint16 newValue);

    /**
     * @notice Emitted when daily consensus rewards change tolerance is updated
     * @param oldValue The old tolerance value
     * @param newValue The new tolerance value
     */
    event DailyConsensusRewardsChangeToleranceBPSUpdated(uint16 oldValue, uint16 newValue);

    /**
     * @notice Emitted when the discount rate is updated
     * @param oldValue The old discount rate
     * @param newValue The new discount rate
     */
    event DiscountRateUpdated(uint16 oldValue, uint16 newValue);

    /**
     * @notice Sets the daily MEV payouts change tolerance in basis points
     * @param newValue The new tolerance value to set
     */
    function setDailyMevPayoutsChangeToleranceBps(uint16 newValue) external;

    /**
     * @notice Sets the daily consensus rewards change tolerance in basis points
     * @param newValue The new tolerance value to set
     */
    function setDailyConsensusRewardsChangeToleranceBps(uint16 newValue) external;

    /**
     * @notice Updates the allowed price change tolerance percentage
     * @param newValue The new discount rate to set
     */
    function setDiscountRate(uint16 newValue) external;

    /**
     * @notice Updates the daily MEV payouts
     * @param newValue The new daily MEV payouts value to set
     */
    function setDailyMevPayouts(uint104 newValue) external;

    /**
     * @notice Updates the daily consensus rewards
     * @param newValue The new daily consensus rewards value to set
     */
    function setDailyConsensusRewards(uint104 newValue) external;

    /**
     * @notice Posts the mint price based on current MEV payouts and consensus rewards
     */
    function postMintPrice() external;

    /**
     * @notice Updates daily rewards and posts the mint price
     * @param dailyMevPayouts The new daily MEV payouts value to set
     * @param dailyConsensusRewards The new daily consensus rewards value to set
     */
    function setDailyRewardsAndPostMintPrice(uint104 dailyMevPayouts, uint104 dailyConsensusRewards) external;

    /**
     * @notice Gets the daily MEV payouts change tolerance in basis points
     * @return The current daily MEV payouts change tolerance in basis points
     */
    function getDailyMevPayoutsChangeToleranceBps() external view returns (uint16);

    /**
     * @notice Gets the daily consensus rewards change tolerance in basis points
     * @return The current daily consensus rewards change tolerance in basis points
     */
    function getDailyConsensusRewardsChangeToleranceBps() external view returns (uint16);

    /**
     * @notice Gets the discount rate in basis points
     * @return The current discount rate in basis points
     */
    function getDiscountRateBps() external view returns (uint16);

    /**
     * @notice Gets the daily MEV payouts
     * @return The current daily MEV payouts
     */
    function getDailyMevPayouts() external view returns (uint104);

    /**
     * @notice Gets the daily consensus rewards
     * @return The current daily consensus rewards
     */
    function getDailyConsensusRewards() external view returns (uint104);
}
