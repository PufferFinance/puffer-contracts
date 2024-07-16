// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Permit } from "../structs/Permit.sol";

/**
 * @title IPufferL2Depositor
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufferL2Depositor {
    /**
     * @notice Thrown supplied token is not valid
     * @dev Signature "0xc1ab6dc1"
     */
    error InvalidToken();
    error InvalidAccount();

    /**
     * @notice Emitted migrator contract is allowed/disallowed
     * @dev Signature "0x65bbc1bef2c9d06930d5ca1aaf28a69cdd4ad19d4d269e57db3605d93e227f9d"
     */
    event SetIsMigratorAllowed(address indexed migrator, bool isAllowed);

    /**
     * @notice Emitted when the new token is added
     * @dev Signature "0xdffbd9ded1c09446f09377de547142dcce7dc541c8b0b028142b1eba7026b9e7"
     */
    event TokenAdded(address indexed token, address pufToken);

    /**
     * @notice Emitted when the new token is added
     * @dev Signature "0xbbe55b1ff108e23e5ff1a6f5d36946eec15ec0ca0ded2bfed4cdcf697ca90460"
     */
    event TokenRemoved(address indexed token, address pufToken);

    /**
     * @notice Emitted when the token is deposited using the depositor
     * @dev Signature "0x1a0b42192bd87f901af5da67a080a510d8c86ccd976904272a9b78c11e7fe085"
     */
    event DepositedToken(
        address indexed token,
        address indexed depositor,
        address indexed account,
        uint256 tokenAmount,
        uint256 referralCode
    );

    event DepositCapUpdated(address indexed token, uint256 oldDepositCap, uint256 newDepositCap);

    /**
     * @notice Deposits `permitData.amount` amount of `token` tokens for the `account`
     * @dev If you are using token.approve() instead of Permit, only populate permitData.amount
     *
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function deposit(
        address token,
        address account,
        Permit calldata permitData,
        uint256 referralCode,
        uint128 lockPeriod
    ) external;

    /**
     * @notice Deposits naative ETH by wrapping it into WETH and then depositing to corresponding token contract
     *
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function depositETH(address account, uint256 referralCode, uint128 lockPeriod) external payable;

    /**
     * @notice Called by the Token contracts to check if the system is paused
     * @dev `restricted` will revert if the system is paused
     */
    function revertIfPaused() external;

    function setDepositCap(address token, uint256 newDepositCap) external;
}
