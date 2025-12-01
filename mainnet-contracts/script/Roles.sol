// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

// Operations & Community multisig have this role
// Operations with 7 day delay, Community 0
// Deprecated
uint64 constant ROLE_ID_UPGRADER = 1;

uint64 constant ROLE_ID_L1_REWARD_MANAGER = 20;
uint64 constant ROLE_ID_REWARD_WATCHER = 21;
uint64 constant ROLE_ID_OPERATIONS_MULTISIG = 22;
uint64 constant ROLE_ID_OPERATIONS_PAYMASTER = 23;
uint64 constant ROLE_ID_OPERATIONS_COORDINATOR = 24;
uint64 constant ROLE_ID_WITHDRAWAL_FINALIZER = 25;
uint64 constant ROLE_ID_REVENUE_DEPOSITOR = 26;

// Role assigned to validator ticket price setter
uint64 constant ROLE_ID_VT_PRICER = 25;

// Role assigned to the Puffer Protocol
uint64 constant ROLE_ID_PUFFER_PROTOCOL = 1234;
uint64 constant ROLE_ID_VAULT_WITHDRAWER = 1235;
uint64 constant ROLE_ID_PUFETH_BURNER = 1236;

uint64 constant ROLE_ID_DAO = 77;
uint64 constant ROLE_ID_GUARDIANS = 88;
uint64 constant ROLE_ID_PUFFER_ORACLE = 999;

// Public role (defined in AccessManager.sol)
uint64 constant PUBLIC_ROLE = type(uint64).max;
// Admin role (defined in AccessManager.sol) (only Timelock.sol must have this role)
uint64 constant ADMIN_ROLE = 0;

// Allowlister role for AVSContractsRegistry
uint64 constant ROLE_ID_AVS_COORDINATOR_ALLOWLISTER = 5;

// Lockbox role for ETH Mainnet
uint64 constant ROLE_ID_LOCKBOX = 7;

// Bridge role for L2RewardManager
uint64 constant ROLE_ID_BRIDGE = 8;
