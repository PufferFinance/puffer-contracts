# Utility scripts

### Validator registration using Safe multisig

1. Make sure that Safe has enough VT & pufETH for the registrations
2. Run the calldata generation script
```bash
forge script script/GenerateBLSKeysAndRegisterValidatorsCalldata.s.sol:GenerateBLSKeysAndRegisterValidatorsCalldata --rpc-url=$ETH_RPC_URL -vvv --ffi
```
3. Copy & paste the addresses & calldata in the Safe Transaction Builder
