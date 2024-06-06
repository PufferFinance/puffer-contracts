# GuardianModule

The `GuardianModule` is a contract that is used to manage the Guardians of the Puffer protocol. Importantly, it ensures that the Guardians are:
- Running an Intel SGX enclave (via the [EnclaveVerifier contract](./EnclaveVerifier.md))
- Producing valid signatures using their whitelisted enclave key or EOA

The `GuardianModule` allows Guardians to update their whitelisted enclave key by calling `rotateGuardianKey()`. For this purpose, we are using the [EnclaveVerifier contract](./EnclaveVerifier.md) to ensure that the Guardians are only registering keys generated from valid enclaves.


## Guardians 

Guardians play a crucial role in Puffer's protocol. They are a collective of respected community members who are deeply aligned with Ethereum's principles and values.

Guardians have two keys to maintain. The first is their EOA (Externally Owned Account) is set in the [`GuardianModule`](../src/`GuardianModule`.sol) when they are registered. The second get is generated in their Intel SGX [enclave](https://en.wikipedia.org/wiki/Trusted_execution_environment) and is used to sign off on provisioning ETH to validators.


The roles of the Guardians are:
- Provisioning new validators who registered
- Skipping malformed validator registrations
- Ejecting validators whose ETH balance has fallen too low or who have run out of [Validator Tickets](ValidatorTicket.md)
- Validator tickets accounting for node operators
- Handling of the full withdrawals requests
- Reporting the total number of active Ethereum validators for enforcing the [BurstThreshold](https://docs.puffer.fi/protocol/burst-threshold)

The Guardians are expected to use their enclave for provisioning, skipping, and ejecting validators. Their EOA wallet is used to sign off on the rest of their duties. A portion of the protocol's fees are awarded to the GuardianModule to subsidize the Guardians' operating costs (infrastructure/gas).


## Important variables
- `_Guardians` is the list of unique addresses of the Guardians.
- `_threshold` represents the minimum number of Guardians that are required to sign off on some operation in the system. It is very similar to threshold of a standard multi-sig wallet. 
- `_mrsigner` is the measurement of the enclave signer.
- `_mrenclave` is the measurement of the enclave.
- `_ejectionThreshold` is the ETH balance threshold that triggers the ejection of a validator. If the validator's balance falls below this threshold, the Guardians will eject the validator.
- `_guardianEnclaves` is a mapping of guardian addresses to their enclave addresses.

## DAO Responsibilities
- Sets the [MRENCLAVE and MRSIGNER](https://www.intel.com/content/www/us/en/developer/articles/technical/introduction-to-intel-sgx-sealing.html) measurements via `setGuardianEnclaveMeasurements`. 
- Adds Guardians via `addGuardian` and removes them via `removeGuardian`
- Sets the `_ejectionThreshold` via `setThreshold`

## Important Functions

### rotateGuardianKey
Guardians can call this function at any time to change their enclave signing key. The key rotation will only be valid if the guardian is using a fresh RAVE(Remote Attestation Verification Evidence) in the transaction. Each guardian will have to call this at least once for initial setup.

### _validateSignatures
This is the most important internal function in the contract as it checks whether the data was signed by the Guardians or is invalid. The ordering of signatures that are submitted to PufferProtocol <strong>MUST</strong> be the same as the one returned from `function getGuardians() returns (address[] memory)` for EOA wallets, and `function getGuardiansEnclaveAddresses() returns(address[] memory)` for enclave signatures.