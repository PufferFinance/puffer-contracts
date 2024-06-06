# AccessManager


The Puffer protocol uses [OpenZepellin's AccessManager](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/74a5d4d4348effabf220ee15909a3aa4467267d5/contracts/access/AccessControlUpgradeable.sol) contract for two purposes: 
1. Setting fine-grained access controls for the protocol's functions.
2. Pausing the system in case of an emergency.

Puffer's [Timelock contract](../lib/pufETH/docs/Timelock.md) is the owner of the `AccessManager`, giving it sole authority to change permissions.

## Deployments

- **AccessManager**: https://etherscan.io/address/0x8c1686069474410e6243425f4a10177a94ebee11
- **Timelock**: https://etherscan.io/address/0x3C28B7c7Ba1A1f55c9Ce66b263B33B204f2126eA

For more information on the deployment, see the [Deployments and ACL](https://github.com/PufferFinance/Deployments-and-ACL/blob/main/docs/deployments/) repository.