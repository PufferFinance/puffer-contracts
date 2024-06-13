// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPufStakingPool
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufStakingPool {
    error InvalidAccount();
    error InvalidAmount();
    error ExpiredSignature();
    error InvalidSignature();
    error MigratorContractNotAllowed(address migrator);

    event Deposited(address indexed from, address indexed to, uint256 amount);
    event Withdrawn(address indexed from, address indexed to, uint256 amount);
    event Migrated(
        address indexed depositor, address indexed destination, address indexed migratorContract, uint256 amount
    );

    function deposit(address account, uint256 amount) external;

    function withdraw(address recipient, uint256 amount) external;

    function migrate(uint256 amount, address migratorContract, address destination) external;

    function migrateWithSignature(
        address depositor,
        address migratorContract,
        address destination,
        uint256 amount,
        uint256 signatureExpiry,
        bytes memory stakerSignature
    ) external;
}
