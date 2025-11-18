# Manual Wiring Guide for pufETH Bridge (Ethereum ↔ Monad)

Since the LayerZero automated wiring tool doesn't support custom endpoint IDs (like Monad's 30390), we need to manually wire the contracts using direct contract calls.

## 📋 Prerequisites

- Contracts deployed on both Ethereum and Monad
- Private key or mnemonic configured in `.env`
- Sufficient gas on both networks
- Contract owner permissions

## 🔧 Wiring Steps

The wiring process has 4 main steps that need to be executed on **both** networks:

### Step 1: Set Peers

This establishes the connection between the two contracts.

**On Ethereum:**
```bash
npx hardhat wire:manual --net ethereum-mainnet --step peer
```

**On Monad:**
```bash
npx hardhat wire:manual --net monad --step peer
```

### Step 2: Set Enforced Options

This configures the gas requirements for cross-chain messages.

**On Ethereum:**
```bash
npx hardhat wire:manual --net ethereum-mainnet --step enforced-options
```

**On Monad:**
```bash
npx hardhat wire:manual --net monad --step enforced-options
```

### Step 3: Set Send Configuration

This configures outgoing message handling (executor and DVN settings).
**Note:** These calls are made to the EndpointV2 contract, not the OFT contract.

**On Ethereum:**
```bash
npx hardhat wire:manual --net ethereum-mainnet --step send-config
```

**On Monad:**
```bash
npx hardhat wire:manual --net monad --step send-config
```

### Step 4: Set Receive Configuration

This configures incoming message handling.
**Note:** These calls are made to the EndpointV2 contract, not the OFT contract.

**On Ethereum:**
```bash
npx hardhat wire:manual --net ethereum-mainnet --step receive-config
```

**On Monad:**
```bash
npx hardhat wire:manual --net monad --step receive-config
```

## 🚀 Quick Start (All Steps)

To execute all steps at once:

**On Ethereum:**
```bash
npx hardhat wire:manual --net ethereum-mainnet --step all
```

**On Monad:**
```bash
npx hardhat wire:manual --net monad --step all
```

## ✅ Verification

After wiring, verify the connections:

**Check Ethereum:**
```bash
npx hardhat wire:check --net ethereum-mainnet
```

**Check Monad:**
```bash
npx hardhat wire:check --net monad
```

You should see that the peer addresses match the expected values.

## 📝 Configuration Details

### Contracts
- **Ethereum (pufETHAdapter):** `0xa4931a9F9Aaf79057334371D6f62164743f97b18`
- **Monad (pufETH):** `0x37D6382B6889cCeF8d6871A8b60E667115eDDBcF`

### Endpoint IDs
- **Ethereum:** `30101`
- **Monad:** `30390`

### Monad LayerZero Infrastructure
- **EndpointV2:** `0x6F475642a6e85809B1c36Fa62763669b1b48DD5B`
- **SendUln302:** `0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7`
- **ReceiveUln302:** `0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043`
- **Executor:** `0x4208D6E27538189bB48E603D6123A94b8Abe0A0b`
- **DVN (Horizen):** `0xdcdd4628f858b45260c31d6ad076bd2c3d3c2f73`
- **DVN (Nethermind):** `0xacde1f22eeab249d3ca6ba8805c8fee9f52a16e7`

### Ethereum LayerZero Infrastructure
- **EndpointV2:** `0x1a44076050125825900e736c501f859c50fE728c`
- **SendUln302:** `0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1`
- **ReceiveUln302:** `0xc02Ab410f0734EFa3F14628780e6e695156024C2`
- **Executor:** `0x173272739Bd7Aa6e4e214714048a9fE699453059`
- **DVN (Horizen):** `0x380275805876ff19055ea900cdb2b46a94ecf20d`
- **DVN (Nethermind):** `0xa59ba433ac34d2927232918ef5b2eaafcf130ba5`

## 🔍 Troubleshooting

### Transaction Fails with "Unauthorized"
Make sure you're using the deployer/owner account that has permissions to configure the contracts.

### Transaction Fails with "Invalid Library"
Verify that the LayerZero infrastructure addresses are correct for your network.

### Peer Not Set Correctly
Make sure you're converting addresses to bytes32 correctly. The script handles this automatically.

## 📚 What Each Step Does

### Set Peer
Links the two contracts together so they know each other's addresses and can communicate.

### Set Enforced Options
Sets minimum gas requirements for message execution on the destination chain. This prevents users from setting gas too low.

### Set Send Configuration
These calls are made to the **EndpointV2 contract** (not the OFT):
- **Send Library:** Sets the message library for outgoing messages
- **Executor Config (configType 1):** The contract that will execute messages on the destination
- **DVN Config (configType 2):** Third-party verifiers (Horizen + Nethermind) that validate cross-chain messages
- **Confirmations:** Number of block confirmations required (15 blocks)

### Set Receive Configuration
These calls are also made to the **EndpointV2 contract** (not the OFT):
- **Receive Library:** Sets the message library for incoming messages
- **ULN Config (configType 2):** Configures which DVNs must verify incoming messages (requires both Horizen + Nethermind)

## 🔐 Security Notes

- Always verify the LayerZero infrastructure addresses before using them
- Use at least one required DVN for security
- Test on testnet first if possible
- Keep the number of confirmations high (15+) for security

## 📞 Support

If you encounter issues:
1. Check that all addresses are correct
2. Verify you have permissions on the contracts
3. Ensure sufficient gas on both networks
4. Contact LayerZero support if infrastructure addresses are incorrect

