// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/manager/AccessManaged.sol";

contract PufToken is ERC20, ERC20Permit {
    address public immutable originalToken;
    address public immutable depositorContract;

    // Custom error definitions
    error TransferFailed();
    error InsufficientBalance();
    error ApprovalFailed();
    error DepositAmountMustBeGreaterThanZero();
    error Unauthorized();

    constructor(string memory name, string memory symbol, address _originalToken, address _depositorContract)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        originalToken = _originalToken;
        depositorContract = _depositorContract;
    }

    modifier onlyDepositor() {
        if (msg.sender != depositorContract) {
            revert Unauthorized();
        }
        _;
    }

    function depositFor(address user, uint256 amount) external onlyDepositor {
        if (amount == 0) {
            revert DepositAmountMustBeGreaterThanZero();
        }

        if (!IERC20(originalToken).transferFrom(user, address(this), amount)) {
            revert TransferFailed();
        }

        _mint(user, amount);
    }

    function withdrawFor(address user, uint256 amount) external onlyDepositor {
        if (balanceOf(user) < amount) {
            revert InsufficientBalance();
        }

        _burn(user, amount);

        if (!IERC20(originalToken).transfer(user, amount)) {
            revert TransferFailed();
        }
    }

    function migrateFor(address user, address migrator, address destination, uint256 amount) external onlyDepositor {
        if (balanceOf(user) < amount) {
            revert InsufficientBalance();
        }

        _burn(user, amount);

        if (!IERC20(originalToken).approve(migrator, amount)) {
            revert ApprovalFailed();
        }

        IMigrator(migrator).migrate(user, originalToken, destination, amount);
    }

    function deposit(uint256 amount) external {
        if (amount == 0) {
            revert DepositAmountMustBeGreaterThanZero();
        }

        if (!IERC20(originalToken).transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }

        _mint(msg.sender, amount);
    }

    function withdraw(uint256 amount) external onlyDepositor {
        if (balanceOf(msg.sender) < amount) {
            revert InsufficientBalance();
        }

        _burn(msg.sender, amount);

        if (!IERC20(originalToken).transfer(msg.sender, amount)) {
            revert TransferFailed();
        }
    }
}

interface IMigrator {
    function migrate(address depositor, address token, address destination, uint256 amount) external;
}
