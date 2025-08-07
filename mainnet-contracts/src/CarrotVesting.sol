// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Carrot Vesting
 * @author Puffer Finance
 * @notice This contract allows users to burn CARROT and start a vesting process to get PUFFER tokens in return
 *         in steps over a period of time
 * @custom:security-contact security@puffer.fi
 */
contract CarrotVesting is Ownable2Step {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error InvalidStartTimestamp();
    error InvalidDuration();
    error InvalidSteps();
    error InvalidMaxCarrotAmount();
    error InvalidTotalPufferRewards();
    error NotStarted();
    error AlreadyStaked();
    error InvalidAmount();
    error NoClaimableAmount();
    error MaxCarrotAmountReached();

    /**
     * @notice Emitted when the contract is initialized
     * @param startTimestamp The timestamp when the vesting starts
     * @param duration The duration of the vesting (seconds since the user stakes)
     * @param steps The number of steps in the vesting (Example: If the vesting is 6 months and the user can claim every month, steps = 6)
     * @param maxCarrotAmount The maximum amount of CARROT that can be staked
     * @param totalPufferRewards The total amount of PUFFER rewards to be distributed
     * @param exchangeRate The exchange rate of PUFFER to CARROT with 18 decimals
     */
    event Initialized(
        uint256 startTimestamp,
        uint256 duration,
        uint256 steps,
        uint256 maxCarrotAmount,
        uint256 totalPufferRewards,
        uint256 exchangeRate
    );

    /**
     * @notice Emitted when a user stakes CARROT
     * @param user The address of the user who staked
     * @param amount The amount of CARROT that was staked
     */
    event Staked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims PUFFER
     * @param user The address of the user who claimed
     * @param claimedAmount The amount of PUFFER that was claimed
     */
    event Claimed(address indexed user, uint256 claimedAmount);

    /**
     * @notice Struct to store the vesting information for a user
     * @param stakedAmount The amount of CARROT that was staked
     * @param claimedAmount The amount of PUFFER that has been claimed so far
     * @param lastClaimedTimestamp The timestamp when the user last claimed
     * @param stakedTimestamp The timestamp when the user staked
     */
    struct Vesting {
        uint256 stakedAmount;
        uint256 claimedAmount;
        uint256 lastClaimedTimestamp;
        uint256 stakedTimestamp;
    }

    IERC20 public immutable CARROT;
    IERC20 public immutable PUFFER;

    uint256 public startTimestamp = type(uint256).max; // Default value is max uint256 instead of 0 to avoid 2 checks in stake function
    uint256 public duration;
    uint256 public steps;
    uint256 public maxCarrotAmount; // This is the total supply of CARROT which is 100M
    uint256 public totalPufferRewards; // This is the total amount of PUFFER rewards to be distributed (55M)
    uint256 public exchangeRate; // This is the exchange rate of PUFFER to CARROT with 18 decimals (55M / 100M = 0.55) * 1e18

    uint256 public totalStakedAmount;

    mapping(address user => Vesting vestingInfo) public vestings;

    constructor(address carrot, address puffer, address initialOwner) Ownable(initialOwner) {
        CARROT = IERC20(carrot);
        PUFFER = IERC20(puffer);
    }

    /**
     * @notice Initializes the contract
     * @dev This function can only be called once by the owner
     * @param _startTimestamp The timestamp when the vesting starts
     * @param _duration The duration of the vesting (seconds since the user stakes)
     * @param _steps The number of steps in the vesting (Example: If the vesting is 6 months and the user can claim every month, steps = 6)
     * @param _maxCarrotAmount The maximum amount of CARROT that can be staked
     * @param _totalPufferRewards The total amount of PUFFER rewards to be distributed
     */
    function initialize(
        uint256 _startTimestamp,
        uint256 _duration,
        uint256 _steps,
        uint256 _maxCarrotAmount,
        uint256 _totalPufferRewards
    ) external onlyOwner {
        require(startTimestamp == type(uint256).max, AlreadyInitialized());
        require(_startTimestamp >= block.timestamp, InvalidStartTimestamp());
        require(_duration > 0, InvalidDuration());
        require(_steps > 0, InvalidSteps());
        require(_maxCarrotAmount > 0, InvalidMaxCarrotAmount());
        require(_totalPufferRewards > 0, InvalidTotalPufferRewards());

        startTimestamp = _startTimestamp;
        duration = _duration;
        steps = _steps;
        maxCarrotAmount = _maxCarrotAmount;
        exchangeRate = 1e18 * _totalPufferRewards / _maxCarrotAmount;
        totalPufferRewards = _totalPufferRewards;
        PUFFER.safeTransferFrom(msg.sender, address(this), _totalPufferRewards);
        emit Initialized(_startTimestamp, _duration, _steps, _maxCarrotAmount, _totalPufferRewards, exchangeRate);
    }

    /**
     * @notice Stakes CARROT to burn them and start the vesting process to get PUFFER tokens in return
     * @param amount The amount of CARROT to stake
     */
    function stake(uint256 amount) external {
        require(block.timestamp >= startTimestamp, NotStarted());
        require(totalStakedAmount + amount <= maxCarrotAmount, MaxCarrotAmountReached());
        Vesting storage vesting = vestings[msg.sender];
        require(vesting.stakedAmount == 0, AlreadyStaked());
        require(amount > 0, InvalidAmount());
        CARROT.safeTransferFrom(msg.sender, address(0xDEAD), amount); // Burn the CARROT
        vesting.stakedAmount = amount;
        vesting.stakedTimestamp = block.timestamp;
        vesting.lastClaimedTimestamp = block.timestamp;
        totalStakedAmount += amount;
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Claims PUFFER tokens from the vesting
     */
    function claim() external returns (uint256) {
        uint256 claimableAmount = calculateClaimableAmount(msg.sender);
        require(claimableAmount > 0, NoClaimableAmount());
        PUFFER.safeTransfer(msg.sender, claimableAmount);
        vestings[msg.sender].lastClaimedTimestamp = block.timestamp;
        vestings[msg.sender].claimedAmount += claimableAmount;
        emit Claimed(msg.sender, claimableAmount);
        return claimableAmount;
    }

    /**
     * @notice Calculates the amount of PUFFER tokens that a user can claim at the current timestamp
     * @dev This calculates the number of steps that has passed since the user staked and then calculates the amount of PUFFER tokens that the user could claim
     *      Then it subtracts the amount of PUFFER tokens that the user has already claimed so far
     * @param user The address of the user to calculate the claimable amount for
     * @return The amount of PUFFER tokens that the user can claim
     */
    function calculateClaimableAmount(address user) public view returns (uint256) {
        Vesting memory vesting = vestings[user];
        if (vesting.stakedAmount == 0) {
            return 0;
        }
        uint256 claimingTimestamp = vesting.stakedTimestamp + duration;
        if (claimingTimestamp > block.timestamp) {
            claimingTimestamp = block.timestamp;
        }
        uint256 numStepsClaimable = (claimingTimestamp - vesting.stakedTimestamp) / (duration / steps);
        uint256 stakedAmountClaimable = (vesting.stakedAmount * numStepsClaimable) / steps;
        uint256 claimableAmount = (stakedAmountClaimable * exchangeRate / 1e18);
        // if(vesting.claimedAmount > claimableAmount) { // Avoid underflow TODO: Check if this is needed
        //     return 0;
        // }
        return claimableAmount - vesting.claimedAmount;
    }
}
