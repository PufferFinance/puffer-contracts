// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { PufToken } from "./PufToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Permit } from "./structs/Permit.sol";
import { IWETH } from "./interface/IWETH.sol";
import { IPufferL2Depositor } from "./interface/IPufferL2Depositor.sol";

/**
 * @title Puffer L2 Depositor contract
 * @author Puffer Finance
 * @notice PufferL2Depositor
 * It has dual purpose:
 * - Factory contract for creating new staking contracts
 * - Helper so that the users can use Permit to deposit the tokens
 * @custom:security-contact security@puffer.fi
 */
contract PufferL2Depositor is IPufferL2Depositor, AccessManaged {
    using SafeERC20 for IERC20;

    address public immutable WETH;

    mapping(address token => address pufToken) public tokens;
    mapping(address migrator => bool isAllowed) public isAllowedMigrator;

    constructor(address accessManager, address weth) AccessManaged(accessManager) {
        WETH = weth;
        _addNewToken(weth);
    }

    modifier onlySupportedTokens(address token) {
        if (tokens[token] == address(0)) {
            revert InvalidToken();
        }
        _;
    }

    /**
     * @inheritdoc IPufferL2Depositor
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function deposit(address token, address account, Permit calldata permitData)
        external
        onlySupportedTokens(token)
        restricted
    {
        // https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#security_considerations
        try ERC20Permit(token).permit({
            owner: msg.sender,
            spender: address(this),
            value: permitData.amount,
            deadline: permitData.deadline,
            v: permitData.v,
            s: permitData.s,
            r: permitData.r
        }) { } catch { }

        IERC20(token).safeTransferFrom(msg.sender, address(this), permitData.amount);

        _deposit({ token: token, depositor: msg.sender, account: account, amount: permitData.amount });
    }

    /**
     * @inheritdoc IPufferL2Depositor
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function depositETH(address account) external payable restricted {
        IWETH(WETH).deposit{ value: msg.value }();

        _deposit({ token: WETH, depositor: msg.sender, account: account, amount: msg.value });
    }

    /**
     * @notice Creates a new staking token contract
     * @dev Restricted to Puffer DAO
     */
    function addNewToken(address token) external restricted {
        _addNewToken(token);
    }

    /**
     * @notice Changes the status of `migrator` to `allowed`
     * @dev Restricted to Puffer DAO
     */
    function setMigrator(address migrator, bool allowed) external restricted {
        if (migrator == address(0)) {
            revert InvalidAccount();
        }
        isAllowedMigrator[migrator] = allowed;
        emit SetIsMigratorAllowed(migrator, allowed);
    }

    /**
     * @notice Changes the status of `migrator` to `allowed`
     * @dev Restricted to Puffer DAO
     */
    function setDepositCap(address token, uint256 newDepositCap) external onlySupportedTokens(token) restricted {
        PufToken pufToken = PufToken(tokens[token]);
        emit DepositCapUpdated(token, pufToken.totalDepositCap(), newDepositCap);
        pufToken.setDepositCap(newDepositCap);
    }

    /**
     * @notice Called by the Token contracts to check if the system is paused
     * @dev `restricted` will revert if the system is paused
     */
    function revertIfPaused() external restricted { }

    function _deposit(address token, address depositor, address account, uint256 amount) internal {
        PufToken pufToken = PufToken(tokens[token]);

        IERC20(token).safeIncreaseAllowance(address(pufToken), amount);

        pufToken.deposit(depositor, account, amount);

        emit DepositedToken(token, msg.sender, account, amount);
    }

    function _addNewToken(address token) internal {
        if (tokens[token] != address(0)) {
            revert InvalidToken();
        }

        string memory symbol = string(abi.encodePacked("puf ", ERC20(token).symbol()));
        string memory name = string(abi.encodePacked("puf", ERC20(token).name()));

        // Reverts on duplicate token
        address pufToken =
            address(new PufToken{ salt: keccak256(abi.encodePacked(token)) }(token, name, symbol, type(uint256).max));

        tokens[token] = pufToken;

        emit TokenAdded(token, pufToken);
    }
}
