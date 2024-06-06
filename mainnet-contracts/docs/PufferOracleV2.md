# PufferOracleV2

The `PufferOracleV2` contract is used to set important variables for the protocol's accounting. 

Traditional liquid staking protocols require an oracle to report the amount of beacon chain ETH that is backing their LST. EIP-4788 allows this to be accomplished trustlessly when combined with a ZKP, but the reserves amount must still be reported and is often subject to sandwich attacks.

Puffer employs "lazy proof of reserves" to circumvent this and simplify the process. Instead of periodically reporting the exact balances of each active validator, the protocol just needs to be aware of the *number* of active validators which is tracked on-chain when validators are provisioned.  

The protocol will perceive all active validators as having a 32 ETH balance, meaning the total ETH on the beacon chain is `_numberOfActivePufferValidators * 32 ETH`. This greatly simplifies the reserves logic but we must account for two cases:
- `balance > 32 ETH`: All surplus ETH is entitled to the node operator due to [Validator Tickets](./ValidatorTicket.md) so it does not count as ETH backing the pufETH token.
- `balance < 32 ETH`: The validator received penalties that will be accounted for when the validator exits the Puffer protocol. 

When the validator's full withdrawal ETH is returned to the protocol, they will receive back their bond and the `_numberOfActivePufferValidators` is decremented, reducing the reserves amount by `32 ETH`. If their exit balance was less than 32 ETH, the difference will be burned from their bond. This process happens atomically to ensure that the pufETH conversion rate remains consistent. 


## Important Functions
### `provisionNode`
Called by the `PufferProtocol` contract when a new validator is provisioned to increase the `_numberOfActivePufferValidators` variable.

### `exitValidators`
Called by the `PufferProtocol` contract when validators fully exit the protocol to decrease the `_numberOfActivePufferValidators` variable.

### `getLockedEthAmount`
Returns the lazily evaluated amount of beacon chain ETH backing the pufETH token: `_numberOfActivePufferValidators * 32 ether`. This value is used when calculating the conversion rate when minting pufETH.

### `setMintPrice`
Used by the DAO to update the price to mint Validator Tickets.

### `setTotalNumberOfValidators`
Reports the number of active validators on Ethereum. This is used to determine if Puffer has hit the 22% BurstThreshold preventing it from threatening consensus thresholds.

### `isOverBurstThreshold`
Returns `true` if Puffer has exceeded it's 22% BurstThreshold causing the ValidatorTicket contract to divert all minting revenue to the treasury to economically slow protocol growth. 