// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPufStakingPool
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufStakingPool {
    /**
     * @notice Thrown when the account is not valid
     * @dev Signature "0x6d187b28"
     */
    error InvalidAccount();

    /**
     * @notice Thrown when signature is expired
     * @dev Signature "0xdf4cc36d"
     */
    error ExpiredSignature();

    /**
     * @notice Thrown when signature is not valid
     * @dev Signature "0x8baa579f"
     */
    error InvalidSignature();

    /**
     * @notice Thrown when the migrator contract is not allowed
     * @dev Signature "0x364938c2"
     */
    error MigratorContractNotAllowed(address migrator);

    /**
     * @notice Thrown when the total deposit cap is reached
     * @dev Signature "0xa5b6cbb3"
     */
    error TotalDepositCapReached();

    /**
     * @notice Emitted when tokens are deposited into the staking pool
     * @param from The address from which the tokens are deposited
     * @param to The address to which the tokens are deposited
     * @param amount The amount of tokens deposited
     */
    event Deposited(address indexed from, address indexed to, uint256 amount);

    /**
     * @notice Emitted when tokens are withdrawn from the staking pool
     * @param from The address from which the tokens are withdrawn
     * @param to The address to which the tokens are withdrawn
     * @param amount The amount of tokens withdrawn
     */
    event Withdrawn(address indexed from, address indexed to, uint256 amount);

    /**
     * @notice Emitted when tokens are migrated
     * @param depositor The address of the depositor
     * @param destination The address of the destination contract
     * @param migratorContract The address of the migrator contract
     * @param amount The amount of tokens migrated
     */
    event Migrated(
        address indexed depositor, address indexed destination, address indexed migratorContract, uint256 amount
    );

    /**
     * @notice Emitted when the deposit cap of a PufStakingPool is changed
     * @param oldDepositCap The previous deposit cap value
     * @param newDepositCap The new deposit cap value
     */
    event DepositCapChanged(uint256 oldDepositCap, uint256 newDepositCap);

    /**
     * @notice Deposits the underlying token to receive pufToken to the `account`
     * @param depositor is the msg.sender or a parameter passed from the PufferL2Depositor
     * @param account is the recipient of the deposit
     * @param amount is the deposit amount
     */
    function deposit(address depositor, address account, uint256 amount) external;

    /**
     * @notice Burns the `amount` of pufToken from the sender and returns the underlying token to the `recipient`
     * @param recipient is the address that will receive the withdrawn tokens
     * @param amount is the amount of tokens to be withdrawn
     */
    function withdraw(address recipient, uint256 amount) external;

    /**
     * @notice Migrates the `amount` of tokens using the allowlsited `migratorContract` to the `destination` address
     * @param amount The amount of tokens to be migrated
     * @param migratorContract The address of the migrator contract
     * @param destination The address of the destination contract
     */
    function migrate(uint256 amount, address migratorContract, address destination) external;

    /**
     * @notice Migrates the tokens using the allowlisted migrator contract using the EIP712 signature from the depositor
     * @param depositor The address of the depositor
     * @param migratorContract The address of the migrator contract
     * @param destination The address of the destination contract
     * @param amount The amount of tokens to be migrated
     * @param signatureExpiry The expiry timestamp of the signature
     * @param stakerSignature The signature provided by the staker
     */
    function migrateWithSignature(
        address depositor,
        address migratorContract,
        address destination,
        uint256 amount,
        uint256 signatureExpiry,
        bytes memory stakerSignature
    ) external;
}
