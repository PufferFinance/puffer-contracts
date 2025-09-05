// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Permit } from "./structs/Permit.sol";
import { InvalidAddress, InvalidAmount } from "./Errors.sol";

/**
 * @title CarrotExchange
 * @author Puffer Finance
 * @notice This contract allows users to swap CARROT to PUFFER at a fixed rate
 * @custom:security-contact security@puffer.fi
 */
contract CarrotExchange is Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    error NotEnoughTimePassed();
    error NotStarted();
    error CarrotExchangeFinished();
    error AlreadyInitialized();
    error InvalidStartTimestamp();

    /**
     * @notice Event emitted when the contract is initialized
     * @param startTimestamp The timestamp when the exchange starts
     * @param pufferRecoveryMinTimestamp The timestamp when the puffer recovery starts
     */
    event Initialized(uint48 startTimestamp, uint48 pufferRecoveryMinTimestamp);

    /**
     * @notice Event emitted when a user swaps CARROT to PUFFER
     * @param user The address of the user who swapped CARROT
     * @param carrotBurned The amount of CARROT that was burned
     * @param pufferReceived The amount of PUFFER that was received
     */
    event CarrotToPufferSwapped(address indexed user, uint256 carrotBurned, uint256 pufferReceived);

    /**
     * @notice Event emitted when the puffer is recovered
     * @param to The address that received the puffer
     * @param amount The amount of puffer that was recovered
     */
    event PufferRecovered(address indexed to, uint256 amount);

    uint256 public constant MIN_TIME_TO_START_PUFFER_RECOVERY = 365 days; // 1 year
    uint256 public constant MAX_CARROT_AMOUNT = 100_000_000 ether; // This is the total supply of CARROT which is 100M
    uint256 public constant TOTAL_PUFFER_REWARDS = 55_000_000 ether; // This is the total amount of PUFFER rewards to be distributed (55M)
    uint256 public constant EXCHANGE_RATE = 1e18 * TOTAL_PUFFER_REWARDS / MAX_CARROT_AMOUNT; // This is the exchange rate of PUFFER to CARROT with 18 decimals (55M / 100M = 0.55) * 1e18

    IERC20 public immutable CARROT;
    IERC20 public immutable PUFFER;

    bool public carrotExchangeFinished;
    uint48 public startTimestamp = type(uint48).max;
    uint48 public pufferRecoveryMinTimestamp = type(uint48).max;
    uint128 public totalCarrotsBurned;

    /**
     * @notice Constructor for the CarrotExchange contract
     * @param carrot The address of the CARROT token
     * @param puffer The address of the PUFFER token
     * @param initialOwner The address of the initial owner
     */
    constructor(address carrot, address puffer, address initialOwner) Ownable(initialOwner) {
        require(carrot != address(0), InvalidAddress());
        require(puffer != address(0), InvalidAddress());
        CARROT = IERC20(carrot);
        PUFFER = IERC20(puffer);
    }

    /**
     * @notice Initializes the contract. It sets the start timestamp and the puffer recovery min timestamp
     *         It also transfers the total puffer rewards to the contract from the msg.sender.
     * @param _startTimestamp The timestamp when the exchange starts
     * @dev Only the owner can initialize the contract
     * @dev The contract can only be initialized once
     */
    function initialize(uint48 _startTimestamp) external onlyOwner {
        require(startTimestamp == type(uint48).max, AlreadyInitialized());
        require(_startTimestamp >= block.timestamp, InvalidStartTimestamp());
        startTimestamp = _startTimestamp;
        pufferRecoveryMinTimestamp = uint48(_startTimestamp + MIN_TIME_TO_START_PUFFER_RECOVERY);
        emit Initialized(startTimestamp, pufferRecoveryMinTimestamp);
        PUFFER.safeTransferFrom(msg.sender, address(this), TOTAL_PUFFER_REWARDS);
    }

    /**
     * @notice Swaps CARROT to PUFFER. It burns the CARROT and transfers the PUFFER to the user.
     * @param carrotAmount The amount of CARROT to swap
     * @dev The contract must be initialized before the swap can be made
     * @dev This can only be done before the puffer recovery flow has been executed
     */
    function swapCarrotToPuffer(uint256 carrotAmount) external {
        _swapCarrotToPuffer(carrotAmount);
    }

    /**
     * @notice Swaps CARROT to PUFFER with a permit. It burns the CARROT and transfers the PUFFER to the user.
     * @param permitData The permit data containing the approval information
     * @dev The contract must be initialized before the swap can be made
     * @dev This can only be done before the puffer recovery flow has been executed
     */
    function swapCarrotToPufferWithPermit(Permit calldata permitData) external {
        IERC20Permit(address(CARROT)).permit(
            msg.sender, address(this), permitData.amount, permitData.deadline, permitData.v, permitData.r, permitData.s
        );
        _swapCarrotToPuffer(permitData.amount);
    }

    /**
     * @notice Recovers the PUFFER. It transfers the PUFFER to the owner.
     * @param to The address that received the puffer
     * @dev Only the owner can recover the PUFFER
     * @dev The PUFFER can only be recovered after the puffer recovery min timestamp
     */
    function recoverPuffer(address to) external onlyOwner {
        require(to != address(0), InvalidAddress());
        require(block.timestamp >= pufferRecoveryMinTimestamp, NotEnoughTimePassed());
        carrotExchangeFinished = true;
        uint256 pufferBalance = PUFFER.balanceOf(address(this));
        PUFFER.safeTransfer(to, pufferBalance);
        emit PufferRecovered(to, pufferBalance);
    }

    /**
     * @notice Pauses the contract. It prevents any swaps from being made.
     * @dev Only the owner can pause the contract
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev Only the owner can unpause the contract
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    /**
     * @notice Swaps CARROT to PUFFER. It burns the CARROT and transfers the PUFFER to the user.
     * @param carrotAmount The amount of CARROT to swap
     * @dev The contract must be initialized before the swap can be made
     * @dev This can only be done before the puffer recovery flow has been executed
     */
    function _swapCarrotToPuffer(uint256 carrotAmount) internal whenNotPaused {
        require(carrotAmount > 0, InvalidAmount());
        require(!carrotExchangeFinished, CarrotExchangeFinished());
        require(block.timestamp >= startTimestamp, NotStarted());
        totalCarrotsBurned += uint128(carrotAmount);
        uint256 pufferAmount = carrotAmount * EXCHANGE_RATE / 1e18;
        emit CarrotToPufferSwapped(msg.sender, carrotAmount, pufferAmount);
        CARROT.safeTransferFrom(msg.sender, address(0xDEAD), carrotAmount);
        PUFFER.safeTransfer(msg.sender, pufferAmount);
    }
}
