# PufferModule
Each `PufferModule` contract will own an [`EigenPod`](https://github.com/Layr-Labs/eigenlayer-contracts/blob/m2-mainnet/src/contracts/pods/EigenPod.sol) and is responsible for managing and interacting with the EigenLayer contracts.

When a `PufferModule` is created, an `EigenPod` is created in the `initialize()` function. Importantly, each `PufferModule` will own exactly one `EigenPod`.

As Puffer's permissionless node operators deploy their validators, they set their *withdrawal credentials* to point to a `PufferModule's` `EigenPod` to participate in restaking.  

`PufferModules` can then delegate their restaked beacon chain ETH to an operator to service AVSs. Importantly, Puffer adds guardrails by restricting `PufferModule` delegations to [RestakingOperator](RestakingOperator.md) contracts, allowing the DAO to have control over the operators and AVSs.

## Consensus Rewards
Over time, consensus rewards accrue in `EigenPods`. Before the rewards can be extracted to the `PufferModule`, EigenLayer requires merkle proofs to be submitted per partial withdrawal and per validator, waiting a week delay, and then finally claiming. 

**WARNING**: Due to the high gas costs of posting merkle proofs, Puffer's initial deployment will not support withdrawing consensus rewards. The EigenLayer team is working towards building batch proofs that will amortize the proving costs across many validators. Until EigenLayer's upgrade, consensus rewards will reside in the `EigenPod`, [`DelayedWithdrawalRouter`](https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/src/contracts/pods/DelayedWithdrawalRouter.sol), or `PufferModule` and will be claimable in the future.

Assuming EigenLayer's improved partial withdrawal proofs are implemented, the `PufferModule` will allow for consensus rewards to be claimed by submitting a merkle proof via the `collectRewards` function. The Guardians will calculate the rewards distributions off-chain and periodically post a merkle root via `postRewardsRoot` on a bi-weekly basis. 

To reduce gas-costs for node operators, each merkle proof will allow them to withdraw the rewards for *all* of their registered validators over the rewards period. 

## Restaking Rewards
EigenLayer's AVS payment system is still in development, so the distribution of restaking rewards to Puffer validators will be added over time.

## Important Functions
### `callStake`
Used to register a new validator to the `EigenPod` and beacon deposit contract. This is only callable by the [`PufferProtocol`](PufferProtocol.md) contract when a Guardian provisions a validator. 

### `callDelegateTo`
Used by the [`PufferModuleManager`](./PufferModuleManager.md) contract to delegate the `EigenPod's` restaked balance to an operator.

### `callUndelegate`
Used by the [`PufferModuleManager`](./PufferModuleManager.md) contract to undelegate the `EigenPod's` restaked balance from an operator.
