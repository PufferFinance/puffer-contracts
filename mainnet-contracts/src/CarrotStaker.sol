// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICarrotStaker } from "./interface/ICarrotStaker.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CarrotStaker
 * @author Puffer Finance
 * @notice Allows users to stake CARROT tokens and receive non-transferable sCarrot tokens
 * @notice The owner cannot disable unstaking once enabled (one-way switch)
 * @custom:security-contact security@puffer.fi
 */
contract CarrotStaker is ERC20, Ownable, ICarrotStaker {
    /*
    * @notice The CARROT token contract
    */
    IERC20 public immutable CARROT;

    /**
     * @notice Whether unstaking is allowed
     */
    bool public isUnstakingAllowed;

    /**
     * @notice Timestamp after which anyone can enable unstaking
     */
    uint256 public constant UNSTAKING_OPEN_TIMESTAMP = 1745193600; // 21 April 2025 00:00:00 GMT

    /**
     * @notice Initializes the contract
     * @param carrot The address of the CARROT token
     * @param initialOwner The address of the admin (IncentiveOps multisig)
     */
    constructor(address carrot, address initialOwner) ERC20("Staked Carrot", "sCarrot") Ownable(initialOwner) {
        CARROT = IERC20(carrot);
    }

    /**
     * @inheritdoc ICarrotStaker
     */
    function stake(uint256 amount) external {
        CARROT.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);

        emit Staked({ staker: msg.sender, amount: amount });
    }

    /**
     * @inheritdoc ICarrotStaker
     */
    function unstake(uint256 amount, address recipient) external {
        require(isUnstakingAllowed, UnstakingNotAllowed());

        _burn(msg.sender, amount);
        CARROT.transfer(recipient, amount);

        emit Unstaked({ staker: msg.sender, recipient: recipient, amount: amount });
    }

    /**
     * @inheritdoc ICarrotStaker
     * @dev Can be called by the owner at any time, or by anyone after UNSTAKING_OPEN_TIMESTAMP
     */
    function allowUnstake() external {
        require(msg.sender == owner() || block.timestamp >= UNSTAKING_OPEN_TIMESTAMP, UnauthorizedUnstakeEnable());
        isUnstakingAllowed = true;
        emit UnstakingAllowed(true);
    }

    /**
     * @notice Prevents approval of sCarrot tokens
     * @dev Overrides the approve function from ERC20
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert MethodNotAllowed();
    }

    /**
     * @notice Prevents transfers of sCarrot tokens
     * @dev Overrides the transfer function from ERC20
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert MethodNotAllowed();
    }

    /**
     * @notice Prevents transfers of sCarrot tokens
     * @dev Overrides the transferFrom function from ERC20
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert MethodNotAllowed();
    }
}
