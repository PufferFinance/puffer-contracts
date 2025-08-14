// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Permit } from "./structs/Permit.sol";
import { InvalidAddress } from "./Errors.sol";

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
    error NotStarted();
    error AlreadyDeposited();
    error InvalidAmount();
    error NoClaimableAmount();

    error NotEnoughTimePassed();
    error InvalidPufferRecoveryStatus(PufferRecoveryStatus status);

    /**
     * @notice Emitted when the contract is initialized
     * @param startTimestamp The timestamp when the vesting starts
     * @param duration The duration of the vesting (seconds since the user deposits)
     * @param steps The number of steps in the vesting (Example: If the vesting is 6 months and the user can claim every month, steps = 6)
     */
    event Initialized(uint256 startTimestamp, uint256 duration, uint256 steps);

    /**
     * @notice Emitted when a user deposits CARROT
     * @param user The address of the user who deposited
     * @param amount The amount of CARROT that was deposited
     */
    event Deposited(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims PUFFER
     * @param user The address of the user who claimed
     * @param claimedAmount The amount of PUFFER that was claimed
     */
    event Claimed(address indexed user, uint256 claimedAmount);

    /**
     * @notice Emitted when the puffer recovery starts
     * @param pufferRecoveryStartTimestamp The timestamp when the puffer recovery starts
     */
    event PufferRecoveryStarted(uint256 pufferRecoveryStartTimestamp);

    /**
     * @notice Emitted when the puffer recovery is completed
     * @param pufferAmountWithdrawn The amount of PUFFER that was withdrawn
     */
    event PufferRecoveryCompleted(uint256 pufferAmountWithdrawn);

    /**
     * @notice Struct to store the vesting information for a user
     * @param depositedAmount The amount of CARROT that was deposited
     * @param claimedAmount The amount of PUFFER that has been claimed so far
     * @param lastClaimedTimestamp The timestamp when the user last claimed
     * @param depositedTimestamp The timestamp when the user deposited
     */
    struct Vesting {
        uint128 depositedAmount;
        uint128 claimedAmount;
        uint48 lastClaimedTimestamp;
        uint48 depositedTimestamp;
    }

    enum PufferRecoveryStatus {
        NOT_STARTED,
        IN_PROGRESS,
        COMPLETED
    }

    uint256 public constant MIN_TIME_TO_START_PUFFER_RECOVERY = 365 days; // 1 year @TODO Check if this is valid
    uint256 public constant PUFFER_RECOVERY_GRACE_PERIOD = 8 * 30 days; // 8 months
    uint256 public constant MAX_CARROT_AMOUNT = 100_000_000 ether; // This is the total supply of CARROT which is 100M
    uint256 public constant TOTAL_PUFFER_REWARDS = 55_000_000 ether; // This is the total amount of PUFFER rewards to be distributed (55M)
    uint256 public constant EXCHANGE_RATE = 1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT; // This is the exchange rate of PUFFER to CARROT with 18 decimals (55M / 100M = 0.55) * 1e18

    IERC20 public immutable CARROT;
    IERC20 public immutable PUFFER;

    // These 4 variables are in just one slot to save gas (48 + 32 + 32 + 128 = 240)
    uint48 public startTimestamp = type(uint48).max; // Default value is max uint48 instead of 0 to avoid 2 checks in deposit function
    uint32 public duration;
    uint32 public steps;
    uint128 public totalDepositedAmount;

    PufferRecoveryStatus public pufferRecoveryStatus;
    uint256 public pufferRecoveryStartTimestamp;

    mapping(address user => Vesting vestingInfo) public vestings;

    constructor(address carrot, address puffer, address initialOwner) Ownable(initialOwner) {
        require(carrot != address(0), InvalidAddress());
        require(puffer != address(0), InvalidAddress());
        CARROT = IERC20(carrot);
        PUFFER = IERC20(puffer);
    }

    /**
     * @notice Initializes the contract
     * @dev This function can only be called once by the owner
     * @param _startTimestamp The timestamp when the vesting starts
     * @param _duration The duration of the vesting (seconds since the user deposits)
     * @param _steps The number of steps in the vesting (Example: If the vesting is 6 months and the user can claim every month, steps = 6)
     */
    function initialize(uint48 _startTimestamp, uint32 _duration, uint32 _steps) external onlyOwner {
        require(startTimestamp == type(uint48).max, AlreadyInitialized());
        require(_startTimestamp >= block.timestamp, InvalidStartTimestamp());
        require(_duration > 0, InvalidDuration());
        require(_steps > 0, InvalidSteps());

        startTimestamp = _startTimestamp;
        duration = _duration;
        steps = _steps;
        PUFFER.safeTransferFrom(msg.sender, address(this), TOTAL_PUFFER_REWARDS);
        emit Initialized({ startTimestamp: _startTimestamp, duration: _duration, steps: _steps });
    }

    /**
     * @notice Deposits CARROT to burn them and start the vesting process to get PUFFER tokens in return
     * @param amount The amount of CARROT to deposit
     */
    function deposit(uint256 amount) external {
        _deposit(amount);
    }

    /**
     * @notice Deposits CARROT to burn them and start the vesting process to get PUFFER tokens in return using a permit
     * @param permitData The permit data
     */
    function depositWithPermit(Permit calldata permitData) external {
        IERC20Permit(address(CARROT)).permit(
            msg.sender, address(this), permitData.amount, permitData.deadline, permitData.v, permitData.r, permitData.s
        );
        _deposit(permitData.amount);
    }

    /**
     * @notice Claims PUFFER tokens from the vesting
     * @return The amount of PUFFER tokens that was claimed
     */
    function claim() external returns (uint128) {
        require(
            pufferRecoveryStatus != PufferRecoveryStatus.COMPLETED, InvalidPufferRecoveryStatus(pufferRecoveryStatus)
        );
        uint128 claimableAmount = calculateClaimableAmount(msg.sender);
        require(claimableAmount > 0, NoClaimableAmount());
        vestings[msg.sender].lastClaimedTimestamp = uint48(block.timestamp);
        vestings[msg.sender].claimedAmount += claimableAmount;
        emit Claimed({ user: msg.sender, claimedAmount: claimableAmount });
        PUFFER.safeTransfer(msg.sender, claimableAmount);
        return claimableAmount;
    }

    /**
     * @notice Starts the puffer recovery process
     * @dev This function can only be called by the owner
     * @dev This initiates the puffer recovery process and sets the puffer recovery start timestamp.
     *      Once it's started, users cannot start new vesting processes. There is a grace period of 8 months after the puffer recovery starts.
     */
    function startPufferRecovery() external onlyOwner {
        require(
            pufferRecoveryStatus == PufferRecoveryStatus.NOT_STARTED, InvalidPufferRecoveryStatus(pufferRecoveryStatus)
        );
        require(block.timestamp >= startTimestamp + MIN_TIME_TO_START_PUFFER_RECOVERY, NotEnoughTimePassed());
        pufferRecoveryStatus = PufferRecoveryStatus.IN_PROGRESS;
        pufferRecoveryStartTimestamp = block.timestamp;
        emit PufferRecoveryStarted(pufferRecoveryStartTimestamp);
    }

    /**
     * @notice Completes the puffer recovery process
     * @dev This function can only be called by the owner
     * @dev This completes the puffer recovery process and transfers the remaining PUFFER tokens to the owner.
     *      Once it's completed, users cannot claim anymore PUFFER tokens (or start new vesting processes).
     */
    function completePufferRecovery() external onlyOwner returns (uint256) {
        require(
            pufferRecoveryStatus == PufferRecoveryStatus.IN_PROGRESS, InvalidPufferRecoveryStatus(pufferRecoveryStatus)
        );
        require(block.timestamp >= pufferRecoveryStartTimestamp + PUFFER_RECOVERY_GRACE_PERIOD, NotEnoughTimePassed());
        pufferRecoveryStatus = PufferRecoveryStatus.COMPLETED;
        uint256 pufferAmountWithdrawn = PUFFER.balanceOf(address(this));
        PUFFER.safeTransfer(msg.sender, pufferAmountWithdrawn);
        emit PufferRecoveryCompleted({ pufferAmountWithdrawn: pufferAmountWithdrawn });
        return pufferAmountWithdrawn;
    }

    /**
     * @notice Calculates the amount of PUFFER tokens that a user can claim at the current timestamp
     * @dev This calculates the number of steps that has passed since the user deposited and then calculates the amount of PUFFER tokens that the user could claim
     *      Then it subtracts the amount of PUFFER tokens that the user has already claimed so far
     * @param user The address of the user to calculate the claimable amount for
     * @return The amount of PUFFER tokens that the user can claim
     */
    function calculateClaimableAmount(address user) public view returns (uint128) {
        Vesting memory vesting = vestings[user];
        if (vesting.depositedAmount == 0) {
            return 0;
        }
        uint256 endOfVesting = vesting.depositedTimestamp + duration;
        if (vesting.lastClaimedTimestamp >= endOfVesting) {
            return 0;
        }
        uint256 claimingTimestamp = endOfVesting > block.timestamp ? block.timestamp : endOfVesting;
        uint256 numStepsClaimable = (claimingTimestamp - vesting.depositedTimestamp) / (duration / steps);
        uint256 depositedAmountClaimable = (vesting.depositedAmount * numStepsClaimable) / steps;
        uint256 claimableAmount = (depositedAmountClaimable * EXCHANGE_RATE / 1e18);
        return uint128(claimableAmount) - vesting.claimedAmount;
    }

    function _deposit(uint256 amount) internal {
        require(
            pufferRecoveryStatus == PufferRecoveryStatus.NOT_STARTED, InvalidPufferRecoveryStatus(pufferRecoveryStatus)
        );
        require(block.timestamp >= startTimestamp, NotStarted());
        Vesting storage vesting = vestings[msg.sender];
        require(vesting.depositedAmount == 0, AlreadyDeposited());
        require(amount > 0, InvalidAmount());
        vesting.depositedAmount = uint128(amount);
        vesting.depositedTimestamp = uint48(block.timestamp);
        vesting.lastClaimedTimestamp = uint48(block.timestamp);
        totalDepositedAmount += uint128(amount);
        emit Deposited({ user: msg.sender, amount: amount });
        CARROT.safeTransferFrom(msg.sender, address(0xDEAD), amount); // Burn the CARROT
    }
}
