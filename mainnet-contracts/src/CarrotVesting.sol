// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Permit } from "./structs/Permit.sol";
import { InvalidAddress } from "./Errors.sol";
import { CarrotVestingStorage } from "./CarrotVestingStorage.sol";
import { Vesting } from "./struct/CarrotVestingStruct.sol";

/**
 * @title Carrot Vesting
 * @author Puffer Finance
 * @notice This contract allows users to burn CARROT and start a vesting process to get PUFFER tokens in return
 *         in steps over a period of time
 * @custom:security-contact security@puffer.fi
 */
contract CarrotVesting is UUPSUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable, CarrotVestingStorage {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error InvalidStartTimestamp();
    error InvalidDuration();
    error InvalidSteps();
    error NotStarted();
    error AlreadyDeposited();
    error InvalidAmount();
    error NoClaimableAmount();
    error AlreadyDismantled();

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
    event VestingStarted(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims PUFFER
     * @param user The address of the user who claimed
     * @param claimedAmount The amount of PUFFER that was claimed
     */
    event Claimed(address indexed user, uint256 claimedAmount);

    /**
     * @notice Emitted when the puffer recovery is done
     * @param pufferAmountWithdrawn The amount of PUFFER that was withdrawn
     */
    event PufferRecovered(uint256 pufferAmountWithdrawn);

    uint256 public constant MAX_CARROT_AMOUNT = 100_000_000 ether; // This is the total supply of CARROT which is 100M
    uint256 public constant TOTAL_PUFFER_REWARDS = 55_000_000 ether; // This is the total amount of PUFFER rewards to be distributed (55M)
    uint256 public constant EXCHANGE_RATE = 1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT; // This is the exchange rate of PUFFER to CARROT with 18 decimals (55M / 100M = 0.55) * 1e18

    IERC20 public immutable CARROT;
    IERC20 public immutable PUFFER;

    constructor(address carrot, address puffer) {
        require(carrot != address(0), InvalidAddress());
        require(puffer != address(0), InvalidAddress());
        CARROT = IERC20(carrot);
        PUFFER = IERC20(puffer);
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @dev This function can only be called once by the owner
     * @param _startTimestamp The timestamp when the vesting starts
     * @param _duration The duration of the vesting (seconds since the user deposits)
     * @param _steps The number of steps in the vesting (Example: If the vesting is 6 months and the user can claim every month, steps = 6)
     * @param initialOwner The address of the owner of the contract
     */
    function initialize(uint48 _startTimestamp, uint32 _duration, uint32 _steps, address initialOwner)
        external
        initializer
    {
        require(_startTimestamp >= block.timestamp, InvalidStartTimestamp());
        require(_duration > 0, InvalidDuration());
        require(_steps > 0, InvalidSteps());

        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __Ownable2Step_init();

        VestingStorage storage $ = _getCarrotVestingStorage();
        $.startTimestamp = _startTimestamp;
        $.duration = _duration;
        $.steps = _steps;
        PUFFER.safeTransferFrom(msg.sender, address(this), TOTAL_PUFFER_REWARDS);
        emit Initialized({ startTimestamp: _startTimestamp, duration: _duration, steps: _steps });
    }

    /**
     * @notice Deposits CARROT to burn them and start the vesting process to get PUFFER tokens in return
     * @param amount The amount of CARROT to deposit
     */
    function startVesting(uint256 amount) external {
        _startVesting(amount);
    }

    /**
     * @notice Deposits CARROT to burn them and start the vesting process to get PUFFER tokens in return using a permit
     * @param permitData The permit data
     */
    function startVestingWithPermit(Permit calldata permitData) external {
        IERC20Permit(address(CARROT)).permit(
            msg.sender, address(this), permitData.amount, permitData.deadline, permitData.v, permitData.r, permitData.s
        );
        _startVesting(permitData.amount);
    }

    /**
     * @notice Claims PUFFER tokens from the vesting
     * @return The amount of PUFFER tokens that was claimed
     */
    function claim() external whenNotPaused returns (uint128) {
        VestingStorage storage $ = _getCarrotVestingStorage();
        require(!$.isDismantled, AlreadyDismantled());
        uint128 totalClaimableAmount;
        uint128 claimableAmount;
        for (uint256 i = 0; i < $.vestings[msg.sender].length; i++) {
            claimableAmount = _calculateClaimableAmount($, msg.sender, i);
            if (claimableAmount > 0) {
                $.vestings[msg.sender][i].lastClaimedTimestamp = uint48(block.timestamp);
                $.vestings[msg.sender][i].claimedAmount += claimableAmount;
                totalClaimableAmount += claimableAmount;
            }
        }
        if (totalClaimableAmount == 0) {
            revert NoClaimableAmount();
        }
        emit Claimed(msg.sender, totalClaimableAmount);
        PUFFER.safeTransfer(msg.sender, totalClaimableAmount);
        return totalClaimableAmount;
    }

    /**
     * @notice Recovers the puffer tokens
     * @param to The address to transfer the PUFFER tokens to
     * @dev This function can only be called by the owner
     * @dev This recovers the puffer tokens and transfers the remaining PUFFER tokens to the owner.
     *      Once it's recovered, users cannot claim anymore PUFFER tokens (or start new vesting processes).
     */
    function recoverPuffer(address to) external onlyOwner returns (uint256) {
        require(to != address(0), InvalidAddress());
        VestingStorage storage $ = _getCarrotVestingStorage();
        $.isDismantled = true;
        uint256 pufferAmountWithdrawn = PUFFER.balanceOf(address(this));
        emit PufferRecovered({ pufferAmountWithdrawn: pufferAmountWithdrawn });
        PUFFER.safeTransfer(to, pufferAmountWithdrawn);
        return pufferAmountWithdrawn;
    }

    /**
     * @notice Pauses the contract
     * @dev This function can only be called by the owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev This function can only be called by the owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Gets all the vestings for a user
     * @param user The address of the user to get the vestings for
     * @return The vestings for the user. This is an array of vestings for the user. Each vesting is a struct that contains:
     *  - the deposited amount
     *  - the claimed amount
     *  - the last claimed timestamp
     *  - the deposited timestamp
     */
    function getVestings(address user) external view returns (Vesting[] memory) {
        VestingStorage storage $ = _getCarrotVestingStorage();
        return $.vestings[user];
    }

    /**
     * @notice Gets the total deposited amount. This is the total amount of CARROT that has been deposited by all users
     * @return The total deposited amount
     */
    function getTotalDepositedAmount() external view returns (uint128) {
        VestingStorage storage $ = _getCarrotVestingStorage();
        return $.totalDepositedAmount;
    }

    /**
     * @notice Gets if the contract is dismantled. Once the contract is dismantled, users cannot start new vesting processes or claim anymore PUFFER tokens
     * @return If the contract is dismantled
     */
    function isDismantled() external view returns (bool) {
        VestingStorage storage $ = _getCarrotVestingStorage();
        return $.isDismantled;
    }

    /**
     * @notice Gets the start timestamp. Users can start depositing CARROT after the start timestamp
     * @return The start timestamp
     */
    function getStartTimestamp() external view returns (uint48) {
        VestingStorage storage $ = _getCarrotVestingStorage();
        return $.startTimestamp;
    }

    /**
     * @notice Gets the duration of the vesting
     * @return The duration of the vesting
     */
    function getDuration() external view returns (uint32) {
        VestingStorage storage $ = _getCarrotVestingStorage();
        return $.duration;
    }

    /**
     * @notice Gets the steps of the vesting
     * @return The steps of the vesting
     */
    function getSteps() external view returns (uint32) {
        VestingStorage storage $ = _getCarrotVestingStorage();
        return $.steps;
    }

    /**
     * @notice Calculates the amount of PUFFER tokens that a user can claim at the current timestamp
     * @dev For each vesting of the user, it calculates the number of steps that has passed since the user deposited and then calculates the amount
     *      of PUFFER tokens that the user could claim. Then it subtracts the amount of PUFFER tokens that the user has already claimed so far
     * @param user The address of the user to calculate the claimable amount for
     * @return The amount of PUFFER tokens that the user can claim
     */
    function calculateClaimableAmount(address user) external view returns (uint256) {
        VestingStorage storage $ = _getCarrotVestingStorage();
        uint256 totalClaimableAmount;
        for (uint256 i = 0; i < $.vestings[user].length; i++) {
            totalClaimableAmount += _calculateClaimableAmount($, user, i);
        }
        return totalClaimableAmount;
    }

    function _calculateClaimableAmount(VestingStorage storage $, address user, uint256 index)
        internal
        view
        returns (uint128)
    {
        Vesting memory vesting = $.vestings[user][index];
        if (vesting.depositedAmount == 0) {
            return 0;
        }
        uint256 endOfVesting = vesting.depositedTimestamp + $.duration;
        if (vesting.lastClaimedTimestamp >= endOfVesting) {
            return 0;
        }
        uint256 claimingTimestamp = endOfVesting > block.timestamp ? block.timestamp : endOfVesting;
        uint256 numStepsClaimable = (claimingTimestamp - vesting.depositedTimestamp) / ($.duration / $.steps);
        uint256 depositedAmountClaimable = (vesting.depositedAmount * numStepsClaimable) / $.steps;
        uint256 claimableAmount = (depositedAmountClaimable * EXCHANGE_RATE / 1e18);
        return uint128(claimableAmount) - vesting.claimedAmount;
    }

    function _startVesting(uint256 amount) internal whenNotPaused {
        VestingStorage storage $ = _getCarrotVestingStorage();
        require(!$.isDismantled, AlreadyDismantled());
        require($.startTimestamp > 0 && block.timestamp >= $.startTimestamp, NotStarted());
        require(amount > 0, InvalidAmount());
        $.vestings[msg.sender].push(
            Vesting({
                depositedAmount: uint128(amount),
                claimedAmount: 0,
                lastClaimedTimestamp: uint48(block.timestamp),
                depositedTimestamp: uint48(block.timestamp)
            })
        );
        $.totalDepositedAmount += uint128(amount);
        emit VestingStarted(msg.sender, amount);
        CARROT.safeTransferFrom(msg.sender, address(0xDEAD), amount); // Burn the CARROT
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Only owner can upgrade the contract
     * @param newImplementation The address of the new implementation
     */
    // slither-disable-next-line dead-code
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}
