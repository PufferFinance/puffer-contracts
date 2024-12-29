# Puffer Contracts

## Grant Payment System Description

The grant payment system is [implemented](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/src/PufferVaultV3.sol) using the pull payment approach by claiming an amount of tokens on the 
grantee's behalf. A list of potential grantees is virtually not restricted, so the best approach
here is to implement it using Merkle proof verification. It is possible to spare on gas costs
by storing only the Merkle root calculated on the basis of a grantee list, instead of storing
all the whitelisted grantees within the vault contract.

The full diff of the changes is within this open [pull request](https://github.com/evercoinx/puffer-contracts/pull/1/files).

## Access Control Lists for Grants

The access control lists for grants rely on the existing Access Manager by defining the required
access restrictions [here](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/script/GenerateAccessManagerCallData.sol#L111).

The grant payments are managed by the [GRANT_MANAGER role](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/script/Roles.sol#L16) who is eligible to [set the Merkle root](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/src/PufferVaultV3.sol#L33) for the grantee list.
It is possible to set a new root whenever a new grantee should be added to the list.

The grant payments are can be [claimed](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/src/PufferVaultV3.sol#L178) solely by an eligible grantee to prevent unauthorized grant claims.
Every grant payment assumes that there is a sufficient amount of Ether or WETH has been already
sent to the vault contract.

## Grant Epochs

The grant payment are restricted to certain time intervals called [grant epochs](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/src/PufferVaultV3.sol#L45). It means that any eligible
grantee is able to claim her full grant during a single epoch only once. It is possbile to claim
a partial grant during this single epoch, but the total amount of claim cannot exceed [the maximum
grant amount](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/src/PufferVaultV3.sol#L33).

## Makefile
For the simplicity sake, all the commands below are defined within the [Makefile](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/Makefile).

## Run Tests for PufferVaultV3
The integration tests are based on the mainnet fork and are located [here](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/test/Integration/PufferVaultV3.fork.t.sol). 

```bash
  cd mainnet-contracts
  make test-puffervaultv3
```

## Deploy PufferVaultV3 into the Holesky network
The deployment script is located [here](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/script/DeployPufferVaultV3.s.sol).

```bash
  cd mainnet-contracts
  make deploy-puffervaultv3-holesky
```

## Upgrade PufferVaultV3 into the Holesky network
The deployment script is located [here](https://github.com/evercoinx/puffer-contracts/blob/vault-grant-payments/mainnet-contracts/script/UpgradePufferVaultV3.s.sol).

```bash
  cd mainnet-contracts
  make upgrade-puffervaultv3-holesky
```

