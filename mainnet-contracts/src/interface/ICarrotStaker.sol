// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

interface ICarrotStaker {
    /**
     * @notice Emitted when a staker stakes CARROT tokens
     * @param staker The address of the staker who staked
     * @param amount The amount of CARROT tokens staked
     */
    event Staked(address indexed staker, uint256 amount);

    /**
     * @notice Emitted when a staker unstakes CARROT tokens
     * @param staker The address of the staker who unstaked
     * @param recipient The address receiving the unstaked CARROT
     * @param amount The amount of CARROT tokens unstaked
     */
    event Unstaked(address indexed staker, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when unstaking is enabled
     * @param allowed The new unstaking status
     */
    event UnstakingAllowed(bool allowed);

    /**
     * @notice Error thrown when unstake is called but unstaking is not allowed
     */
    error UnstakingNotAllowed();

    /**
     * @notice Error thrown when someone tries to approve or transfer sCarrot tokens
     */
    error MethodNotAllowed();

    /**
     * @notice Error thrown when caller is not owner or unstaking is not open yet
     */
    error UnauthorizedUnstakeEnable();

    /**
     * @return Whether unstaking is allowed
     */
    function isUnstakingAllowed() external view returns (bool);

    /**
     * @notice Stakes CARROT tokens
     * @param amount The amount of CARROT tokens to stake
     */
    function stake(uint256 amount) external;

    /**
     * @notice Unstakes CARROT tokens
     * @param amount The amount of CARROT tokens to unstake
     * @param recipient The address to receive the unstaked CARROT tokens
     */
    function unstake(uint256 amount, address recipient) external;

    /**
     * @notice Enables unstaking of CARROT tokens
     * @notice Once enabled, the owner cannot disable unstaking (one-way switch)
     * @dev Can only be called by the owner
     */
    function allowUnstake() external;
}
