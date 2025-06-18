# PufferVault V5

The PufferVaultV5 contract is the latest upgrade to the Puffer Vault, responsible for custodying funds for the Puffer protocol. It inherits from PufferVaultStorage and implements various interfaces including IPufferVaultV5, IERC721Receiver, AccessManagedUpgradeable, ERC20PermitUpgradeable, ERC4626Upgradeable, and UUPSUpgradeable.

The PufferVaultV5 contract is a modified ERC4626 vault with custom logic to handle deposits of stETH and ETH in addition to the standard WETH. It extends the ERC4626Upgradeable contract and overrides key functions like `deposit`, `mint`, `withdraw`, and `redeem` to support these additional asset types. The vault tracks the total assets across ETH, stETH, and WETH balances, and handles conversions between these asset types as needed. It also integrates with Lido for stETH withdrawals. Overall, PufferVaultV5 provides a custodial vault tailored for the Puffer protocol's unique requirements while adhering to the ERC4626 standard for compatibility.

## Core Functionality

The vault manages deposits and withdrawals of ETH, stETH, and WETH while minting pufETH tokens to represent user shares. It handles:

- WETH/ETH/stETH deposits and conversions to pufETH
- Withdrawals of WETH in exchange for pufETH
- Reward distribution and management
- Integration with Lido for stETH withdrawals

## Key Components

### Important State Variables

- `_ST_ETH`: Lido's stETH contract address
- `_LIDO_WITHDRAWAL_QUEUE`: Lido's withdrawal queue contract
- `_WETH`: Wrapped ETH contract
- `PUFFER_ORACLE`: Oracle for proof-of-reserves
- `RESTAKING_REWARDS_DEPOSITOR`: Contract for depositing rewards

## Core Functions

### Deposit Functions

#### `depositETH`

Allows users to deposit native ETH and receive pufETH tokens in return.

#### `depositStETH`

Enables deposits of stETH shares in exchange for pufETH tokens.

#### `mint`

```solidity
function mint(uint256 shares, address receiver) public returns (uint256)
```

Mints `shares` pufETH tokens and transfers them to `receiver`. Standard ERC4626 mint function.

#### `deposit`

```solidity
function deposit(uint256 assets, address receiver) public returns (uint256)
```

Deposits `assets` (WETH) and mints the corresponding amount of pufETH tokens to `receiver`. Standard ERC4626 deposit function.

### Withdrawal Functions

#### `withdraw`

```solidity
function withdraw(uint256 assets, address receiver, address owner) public returns (uint256)
```

Withdraws WETH assets from the vault by burning pufETH shares. Standard ERC4626 withdraw function.

#### `redeem`

```solidity
function redeem(uint256 shares, address receiver, address owner) public returns (uint256)
```

Redeems pufETH shares for WETH assets. Standard ERC4626 redeem function.

### Reward Management

#### `mintRewards`

```solidity
function mintRewards(uint256 rewardsAmount) external returns (uint256 ethToPufETHRate, uint256 pufETHAmount)
```

Mints pufETH rewards for the L1RewardManager contract. The rewards are then bridged to Base. On Base the Node operators can claim the rewards.

#### `depositRewards`

```solidity
function depositRewards() external payable
```

Deposits rewards to the vault and updates total reward deposit amount.

### Lido Integration

#### `initiateETHWithdrawalsFromLido`

```solidity
function initiateETHWithdrawalsFromLido(uint256[] calldata amounts) external returns (uint256[] memory)
```

Initiates ETH withdrawals from Lido by queueing withdrawal requests.

#### `claimWithdrawalsFromLido`

```solidity
function claimWithdrawalsFromLido(uint256[] calldata requestIds) external
```

Claims completed ETH withdrawals from Lido.

### Asset Transfer

#### `transferETH`

```solidity
function transferETH(address to, uint256 ethAmount) external
```

Transfers ETH to PufferModules for validator funding.

### Fee Management

#### `setExitFeeBasisPoints`

```solidity
function setExitFeeBasisPoints(uint256 newExitFeeBasisPoints) external
```

Sets the exit fee basis points (max 2.5%). This exit fee is distributed to all pufETH holders.

#### `setTreasuryExitFeeBasisPoints`

```solidity
function setTreasuryExitFeeBasisPoints(uint256 newTreasuryExitFeeBasisPoints, address newTreasury) external
```

Sets the treasury exit fee basis points (max 2.5%). This exit fee is distributed to the treasury. If the treasury exit fee basis points is set to 0, the treasury address must be set to address(0).

### View Functions

#### `totalAssets`

```solidity
function totalAssets() public view returns (uint256)
```

Calculates total assets by summing:

- WETH balance
- ETH balance
- Oracle-reported locked ETH
- Total reward mint amount
- Minus pending distributions and deposits

#### `getPendingLidoETHAmount`

```solidity
function getPendingLidoETHAmount() public view returns (uint256)
```

Returns amount of ETH pending withdrawal from Lido.

#### `getTotalRewardMintAmount`

```solidity
function getTotalRewardMintAmount() public view returns (uint256)
```

Returns total minted rewards amount.

#### `getTotalRewardDepositAmount`

```solidity
function getTotalRewardDepositAmount() public view returns (uint256)
```

Returns total deposited rewards amount.

## Events

### `UpdatedTotalRewardsAmount`

```solidity
event UpdatedTotalRewardsAmount(uint256 previousTotalRewardsAmount, uint256 newTotalRewardsAmount, uint256 depositedETHAmount)
```

Emitted when rewards are deposited to the vault.

### `RequestedWithdrawals`

```solidity
event RequestedWithdrawals(uint256[] requestIds)
```

Emitted when withdrawals are requested from Lido.

### `ClaimedWithdrawals`

```solidity
event ClaimedWithdrawals(uint256[] requestIds)
```

Emitted when withdrawals are claimed from Lido.

### `TransferredETH`

```solidity
event TransferredETH(address to, uint256 amount)
```

Emitted when ETH is transferred to a PufferModule.

## Security Features

- Access control via AccessManagedUpgradeable
- Deposit tracking to prevent simultaneous deposits/withdrawals
- Maximum exit fee of 5%
- Upgradeable via UUPS pattern
- Secure ETH handling with fallback functions

## Integration Points

- EigenLayer for restaking
- Lido for stETH operations
- Puffer Oracle for proof-of-reserves on Beacon Chain
- Revenue Depositor for reward distribution

The contract serves as the core vault for the Puffer protocol, managing user deposits and withdrawals.
