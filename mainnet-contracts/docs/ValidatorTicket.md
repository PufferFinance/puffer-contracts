# Validator Ticket

You can think of [validator tickets](https://docs.puffer.fi/protocol/validator-tickets) (VTs) as validator time at a discounted price. In order to run validators in Puffer, node operators lock VT ERC20s in the `PufferProtocol` contract. 

Each validator consumes 1 VT per day they are active. Importantly, VTs are consumed only after the validator has been activated on the beacon chain, meaning their tickets are not expiring while in the queueing process. All VT accounting is performed off-chain by the Guardians and the VT mint price is set by the [PufferOracle](./PufferOracleV2.md). 

When VTs are purchased:
- a portion of the funds go to the protocol's treasury
- a portion of the funds go to the Guardians to subsidize their operating costs
- the remainder goes to the `PufferVault` as rewards, increasing pufETH value

## Important Functions
### `purchaseValidatorTicket`
Called by anyone to mint ValidatorTicket ERC20s.

### `burn`
Called by the `PufferProtocol` contract when a Puffer validator exits the protocol or is skipped during registration to burn ValidatorTicket ERC20s. 

### `setProtocolFeeRate`
Called by the DAO to set the percentage of VT minting revenue that goes to the treasury.

### `setGuardiansFeeRate`
Called by the DAO to set the percentage of VT minting revenue that goes to the Guardians.
