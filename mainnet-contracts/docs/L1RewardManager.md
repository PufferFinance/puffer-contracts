# L1RewardManager

The L1RewardManager contract mints the pufETH rewards of the Puffer node operators and lets them claim the rewards with a merkle proof on Ethereum Mainnet. It inherits from L1RewardManagerStorage and implements IL1RewardManager, AccessManagedUpgradeable and UUPSUpgradeable.

The rewards are processed in intervals. An interval is a range of beacon chain epochs. For every interval the rewards minter mints the total ETH rewards of the interval as pufETH through the PufferVault and stores the merkle root of the rewards. The pufETH stays in the L1RewardManager until the node operators claim it. Each node operator claims its share with a merkle proof, after a claiming delay. During the claiming delay a wrong interval can be frozen and reverted.

The previous version of the contract bridged the minted pufETH to Base with LayerZero, and the node operators claimed the rewards on the L2RewardManager on Base. That version is replaced by this one. The L2RewardManager on Base stays in claim-only mode for the intervals that were bridged before the upgrade.

## Core Functionality

- Minting the pufETH rewards of an interval, limited by an allowed mint amount and an allowed mint frequency
- Claiming the rewards with a merkle proof, after a claiming delay
- Freezing and reverting a wrong interval during its claiming delay

## Interval Lifecycle

```
mintRewards ──► ACTIVE ──(claiming delay passes)──► claimable
                  │
                  │ freezeInterval (only during the claiming delay)
                  ▼
                FROZEN ──revertInterval──► REVERTED ──► the epoch range can be minted again
```

- `NONE`: The interval does not exist
- `ACTIVE`: The rewards are minted. They can be claimed from `claimableAt`
- `FROZEN`: The claiming is stopped. The interval can only be reverted, there is no unfreeze
- `REVERTED`: The minted pufETH is burned. The interval can not be claimed

Only the newest interval can be frozen, and only before its claiming starts. A new interval can only be minted after the claiming delay of the newest interval has passed and the newest interval is not frozen. Because of this, nothing was ever claimed from a frozen interval, and a revert always moves the epoch pointer back by exactly one interval.

## Key Components

### Important State Variables

- `PUFFER_VAULT`: The PufferVault (pufETH) contract on Ethereum Mainnet (immutable)
- `allowedRewardMintAmount`: The maximum ETH amount of one interval
- `allowedRewardMintFrequency`: The minimum time between two mints (at least 72 hours)
- `lastRewardMintTimestamp`: The timestamp of the last mint
- `lastIntervalEndEpoch`: The last successfully processed interval end epoch
- `currentIntervalEndEpoch`: The end epoch of the newest interval
- `claimingDelay`: The delay between the mint of an interval and the start of its claiming (between 6 and 72 hours)
- `newestIntervalId`: The ID of the newest minted interval, the only interval that can be frozen
- `intervals`: The interval records (epochs, amounts, exchange rate, merkle root, `claimableAt`, status)
- `claimedRewards`: Tracks which accounts already claimed the rewards of an interval

The `claimableAt` timestamp of an interval is fixed when the interval is minted. A later change of the claiming delay does not change it.

## Core Functions

### Minting

#### `mintRewards`

```solidity
function mintRewards(MintRewardsParams calldata params) external
```

Mints the pufETH rewards of an interval into this contract and stores the merkle root. `params` has the ETH rewards amount, the start and end epoch, the merkle root and the URI of the rewards metadata. It reverts if:

- the rewards amount is 0 or higher than `allowedRewardMintAmount`
- the last mint was less than `allowedRewardMintFrequency` ago
- the newest interval is still in its claiming delay, or is frozen
- the start epoch is not after the end epoch of the previous interval

The ETH to pufETH exchange rate of the mint is stored with the interval and is used for all claims of the interval.

Restricted to `ROLE_ID_REWARDS_MINTER` (28). The role is granted through the Timelock before a mint and revoked after it.

### Claiming

#### `claimRewards`

```solidity
function claimRewards(ClaimOrder[] calldata claimOrders) external
```

Claims the rewards of one or more intervals. Each claim order has the interval ID, the ETH amount, the `isL1Contract` flag, the account and the merkle proof. The leaf is:

```solidity
keccak256(bytes.concat(keccak256(abi.encode(account, isL1Contract, amount))))
```

The leaf format is the same as on the L2RewardManager. The `isL1Contract` flag is part of the leaf, but it has no effect on L1. The pufETH amount is `amount * ethToPufETHRate / 1 ether` and it is always sent to `account`, so anyone can claim for anyone. An interval can never pay out more pufETH than was minted for it.

Public.

### Freeze and Revert

#### `freezeInterval`

```solidity
function freezeInterval(uint256 startEpoch, uint256 endEpoch) external
```

Freezes the newest interval during its claiming delay. A frozen interval can not be claimed and can only be reverted. Restricted to `ROLE_ID_REWARD_WATCHER` (21).

#### `revertInterval`

```solidity
function revertInterval(uint256 startEpoch, uint256 endEpoch) external
```

Reverts a frozen interval. It burns the minted pufETH through `PufferVault.revertMintRewards`, subtracts the ETH amount from the vault's reward mint amount, and moves the epoch pointer back, so the same epoch range can be minted again. Restricted to `ROLE_ID_DAO` (77).

#### `freezeAndRevertInterval`

```solidity
function freezeAndRevertInterval(uint256 startEpoch, uint256 endEpoch) external
```

Freezes and reverts the newest interval in one call. Restricted to `ROLE_ID_DAO` (77).

### Configuration

#### `setAllowedRewardMintAmount`

```solidity
function setAllowedRewardMintAmount(uint104 newAmount) external
```

Sets the maximum ETH amount of one interval. Restricted to `ROLE_ID_DAO` (77).

#### `setAllowedRewardMintFrequency`

```solidity
function setAllowedRewardMintFrequency(uint104 newFrequency) external
```

Sets the minimum time between two mints. It must be at least 72 hours. Restricted to `ROLE_ID_DAO` (77).

#### `setClaimingDelay`

```solidity
function setClaimingDelay(uint256 newDelay) external
```

Sets the claiming delay for new intervals. It must be between 6 and 72 hours. Already minted intervals keep their `claimableAt`. Restricted to `ROLE_ID_DAO` (77).

### Upgrade

#### `initializeV2`

```solidity
function initializeV2(uint256 claimingDelay, uint104 allowedRewardMintFrequency, address deprecatedPufETHOFTAdapter) external
```

Initializes the upgrade from the bridging version. It sets the claiming delay and the mint frequency, and sets the leftover pufETH allowance of this contract to the LayerZero pufETH OFT adapter to 0. It must be called in the same transaction as the upgrade (`upgradeToAndCall`). Restricted to the AccessManager admin (Timelock).

### View Functions

#### `getIntervalId`

```solidity
function getIntervalId(uint256 startEpoch, uint256 endEpoch) public pure returns (bytes32)
```

Returns `keccak256(abi.encodePacked(startEpoch, endEpoch))`.

#### `getInterval`

```solidity
function getInterval(bytes32 intervalId) external view returns (Interval memory)
```

Returns the interval record.

#### `isClaimed`

```solidity
function isClaimed(bytes32 intervalId, address account) external view returns (bool)
```

Returns true if the account already claimed the rewards of the interval.

#### `isClaimingLocked`

```solidity
function isClaimingLocked(bytes32 intervalId) external view returns (bool)
```

Returns true if the interval can not be claimed now: it is not active, or its claiming delay has not passed.

#### `getClaimingDelay`

```solidity
function getClaimingDelay() external view returns (uint256)
```

Returns the claiming delay for new intervals.

#### `getNewestIntervalId`

```solidity
function getNewestIntervalId() external view returns (bytes32)
```

Returns the ID of the newest minted interval.

#### `getLastIntervalEndEpoch` / `getCurrentIntervalEndEpoch`

```solidity
function getLastIntervalEndEpoch() external view returns (uint256)
function getCurrentIntervalEndEpoch() external view returns (uint256)
```

Return the end epoch of the interval before the newest one, and the end epoch of the newest interval. The next interval must start after `getCurrentIntervalEndEpoch()`.

## Events

### `RewardsMinted`

```solidity
event RewardsMinted(bytes32 indexed intervalId, bytes32 indexed rewardsRoot, uint256 rewardsAmount, uint256 pufETHAmount, uint256 ethToPufETHRate, uint256 startEpoch, uint256 endEpoch, uint256 claimableAt, string rewardsURI)
```

Emitted when the rewards of an interval are minted.

### `RewardsClaimed`

```solidity
event RewardsClaimed(address indexed account, bytes32 indexed intervalId, uint256 amount, uint256 pufETHAmount)
```

Emitted when an account claims the rewards of an interval.

### `IntervalFrozen`

```solidity
event IntervalFrozen(bytes32 indexed intervalId, uint256 startEpoch, uint256 endEpoch)
```

Emitted when an interval is frozen.

### `RevertedRewards`

```solidity
event RevertedRewards(uint256 rewardsAmount, uint256 startEpoch, uint256 endEpoch, bytes32 indexed rewardsRoot)
```

Emitted when a frozen interval is reverted.

### `AllowedRewardMintAmountUpdated`, `AllowedRewardMintFrequencyUpdated`, `ClaimingDelayUpdated`

```solidity
event AllowedRewardMintAmountUpdated(uint256 oldAmount, uint256 newAmount)
event AllowedRewardMintFrequencyUpdated(uint256 oldFrequency, uint256 newFrequency)
event ClaimingDelayUpdated(uint256 oldDelay, uint256 newDelay)
```

Emitted when the configuration changes.

## Security Features

- Access control via AccessManagedUpgradeable
- The mint amount and the mint frequency are limited
- A claiming delay between the mint and the claims, during which the reward watcher can freeze a wrong interval
- Only the newest interval can be frozen and reverted, and only before its claiming starts, so nothing was claimed from a reverted interval
- An interval can never pay out more pufETH than was minted for it, which limits a wrong merkle root to its own interval
- Merkle leaves are hashed twice to prevent second preimage attacks
- Upgradeable via UUPS pattern, the upgrade is restricted to the AccessManager admin

## Integration Points

- PufferVault for minting (`mintRewards`) and burning (`revertMintRewards`) the pufETH rewards
- The off-chain rewards service, which calculates the rewards and the merkle tree of each interval
- The reward watcher, which checks every minted interval during the claiming delay
- L2RewardManager on Base, in claim-only mode for the intervals bridged before the upgrade
