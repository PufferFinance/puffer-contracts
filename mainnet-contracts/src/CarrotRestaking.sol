// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICarrotRestaking } from "./interface/ICarrotRestaking.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CarrotRestaking
 * @author Puffer Finance
 * @notice Allows users to stake CARROT tokens and receive non-transferable sCarrot tokens
 * @notice The owner cannot disable unstaking once enabled (one-way switch)
 * @custom:security-contact security@puffer.fi
 */
contract CarrotRestaking is ERC20, Ownable, ICarrotRestaking {
    /*
    * @notice The CARROT token contract
    */
    IERC20 public immutable CARROT;

    /**
     * @notice Whether unstaking is allowed
     */
    bool public isUnstakingAllowed;

    /**
     * @notice Initializes the contract
     * @param carrot The address of the CARROT token
     * @param initialOwner The address of the admin (IncentiveOps multisig)
     */
    constructor(address carrot, address initialOwner) ERC20("Staked Carrot", "sCarrot") Ownable(initialOwner) {
        CARROT = IERC20(carrot);
    }

    /**
     * @inheritdoc ICarrotRestaking
     */
    function stake(uint256 amount) external {
        CARROT.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);

        emit Staked({ staker: msg.sender, amount: amount });
    }

    /**
     * @inheritdoc ICarrotRestaking
     */
    function unstake(uint256 amount, address recipient) external {
        if (!isUnstakingAllowed) revert UnstakingNotAllowed();

        _burn(msg.sender, amount);
        CARROT.transfer(recipient, amount);

        emit Unstaked({ staker: msg.sender, recipient: recipient, amount: amount });
    }

    /**
     * @inheritdoc ICarrotRestaking
     * @dev Can only be called by the owner
     */
    function allowUnstake() external onlyOwner {
        isUnstakingAllowed = true;
        emit UnstakingAllowed({ allowed: true });
    }

    /**
     * @notice Prevents transfers of sCarrot tokens
     * @dev Overrides the transfer function from ERC20
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransferNotAllowed();
    }

    /**
     * @notice Prevents transfers of sCarrot tokens
     * @dev Overrides the transferFrom function from ERC20
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransferNotAllowed();
    }
}
