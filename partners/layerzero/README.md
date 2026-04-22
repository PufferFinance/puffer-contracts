# LayerZero Bridge Scripts

Scripts for deploying and wiring LayerZero OFT/OFTAdapter contracts for cross-chain token bridging.

## Prerequisites

- Node.js (v18+)
- pnpm package manager

## Installation

```bash
pnpm install
```

## Configuration

1. Copy `.env.example` to `.env` and fill in required values:
   - `PRIVATE_KEY` or `MNEMONIC` for transaction signing (not needed for wiring, since all contracts are owned by multisigs)
   - RPC URLs (optional - defaults provided)
   - Explorer API keys (optional - for verification)

2. Chain configurations are in `config/chains/`. Each chain has:
   - Network details (chainId, RPC, explorer)
   - LayerZero infrastructure addresses (endpoint, DVNs, executor)
   - Wiring parameters (confirmations, gas limits)
   - Deployed contract addresses

## Adding a New Chain

### Finding LayerZero Deployment Addresses

LayerZero maintains a metadata API with all deployment addresses for each chain:

**https://metadata.layerzero-api.com/v1/metadata/deployments**

From this API, you'll need:

- `endpointV2` - The main LayerZero endpoint contract
- `sendUln302` / `receiveUln302` - Message library contracts
- `executor` - The executor contract for your chain
- `dvns` - DVN (Decentralized Verifier Network) addresses (e.g., Horizen, Nethermind) (Remember to add same nos. of DVNs to both source and destination chains)

### Creating the Chain Config

1. Create a new config file in `config/chains/`:

```typescript
// config/chains/mychain.ts
import { CustomChainConfig } from '../types'

export const MYCHAIN_EID = 30XXX // LayerZero endpoint ID

export const mychain: CustomChainConfig = {
    name: 'mychain',
    chainId: 1234,
    eid: MYCHAIN_EID,
    rpcUrl: process.env.MYCHAIN_RPC_URL || 'https://rpc.mychain.com',
    timeout: 120000,
    explorer: {
        apiUrl: 'https://explorer.mychain.com/api',
        browserUrl: 'https://explorer.mychain.com',
        apiKey: process.env.MYCHAIN_EXPLORER_API_KEY || 'mychain',
    },
    layerzero: {
        endpointV2: '0x...',
        sendUln302: '0x...',
        receiveUln302: '0x...',
        executor: '0x...',
        dvns: {
            required: ['0x...'], // Required DVN addresses
            optional: [],
        },
    },
    wiring: {
        confirmations: 5,
        executorMaxMessageSize: 10000,
        lzReceiveGas: 80000,
    },
    contracts: {
        // Add deployed contract addresses here
        // pufETH: '0x...',
    },
    tokenType: 'OFT', // or 'OFTAdapter' for source chain
}
```

2. Export it from `config/chains/index.ts`

3. List available chains:

```bash
npx hardhat custom:chains
```

## Deploying Contracts

Deploy OFT contract to a new chain:

```bash
npx hardhat deploy --network mychain --tags pufETH
```

The deployment script will automatically attempt verification after deployment.

## Wiring Contracts

Wire contracts between Ethereum (source) and a destination chain. The script always generates Safe multisig calldata — it never sends transactions from an EOA, because both the source `OFTAdapter` and the destination `OFT` (including their LayerZero delegate) are owned by multisigs.

```bash
npx hardhat custom:wire --token pufETH --dest megaeth
```

### Options

| Option          | Description                                                                                                                        | Default          |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `--token`       | Token to wire (pufETH or PUFFER)                                                                                                   | required         |
| `--dest`        | Destination chain name                                                                                                             | required         |
| `--source`      | Source chain name                                                                                                                  | ethereum-mainnet |
| `--restart`     | Ignore saved state and start fresh                                                                                                 | false            |
| `--dry-run`     | Simulate each call from the impersonated owner/delegate via `eth_call`, print calldata, and skip writing state or Safe batch files | false            |
| `--source-only` | Only wire source chain                                                                                                             | false            |
| `--dest-only`   | Only wire destination chain                                                                                                        | false            |

### Output

For each chain wired, the script writes a Gnosis Safe batch JSON to `.wiring-state/safe-batch-<chain>-<token>.json` containing all 4 transactions:

1. `setPeer` — on the OFT/OFTAdapter
2. `setEnforcedOptions` — on the OFT/OFTAdapter
3. `setSendConfig` — on EndpointV2
4. `setReceiveConfig` — on EndpointV2

### Resume Support

The wiring script saves state to `.wiring-state/` and can resume from where it left off. Use `--restart` to start fresh.

### Example: Wire to MegaETH

```bash
# Generate Safe batches for both chains
npx hardhat custom:wire --token pufETH --dest megaeth

# Only generate the destination-chain Safe batch
npx hardhat custom:wire --token pufETH --dest megaeth --dest-only

# Dry run: preview calldata and simulate each call as the owner/delegate
# (nothing is written — use this to sanity-check before committing the Safe batch)
npx hardhat custom:wire --token pufETH --dest megaeth --dry-run
```

In `--dry-run`, the script reads `owner()` on the OFT/OFTAdapter and `delegates(oapp)` on EndpointV2, then issues an `eth_call` against each generated calldata with `from` set to that address. A `[SIMULATE]` line is printed per transaction:

- `OK (from 0x…)` — the call would succeed if executed by the impersonated sender
- `REVERT — <reason>` — the call would revert (e.g. not owner, delegate unset, invalid config)

Simulation runs against current on-chain state, so a later call may still revert if an earlier call in the batch is a prerequisite and hasn't been executed yet.

## Checking Wiring Status

Verify that contracts are properly wired:

```bash
npx hardhat custom:check --token pufETH --dest megaeth
```

## Multisig Workflow

Both the source chain `OFTAdapter` and the destination chain `OFT` (and the LayerZero delegate on `EndpointV2`) are owned by multisigs, so every wiring transaction must be routed through Safe. The script reflects this: it always produces calldata, never broadcasts from an EOA.

### Understanding the Wiring Process

The wiring process involves 4 transactions on each chain, all of which must be signed by the owning multisig:

| #   | Transaction          | Contract         | Who Can Execute   |
| --- | -------------------- | ---------------- | ----------------- |
| 1   | `setPeer`            | OFT / OFTAdapter | Owner multisig    |
| 2   | `setEnforcedOptions` | OFT / OFTAdapter | Owner multisig    |
| 3   | `setSendConfig`      | EndpointV2       | Delegate multisig |
| 4   | `setReceiveConfig`   | EndpointV2       | Delegate multisig |

> **Ordering note:** `setSendConfig` / `setReceiveConfig` may revert on-chain if the peer is not set yet. When queuing the batch in Safe, ensure `setPeer` is the first transaction in the bundle (it is in the order produced by this script).

### Step 1: Generate Safe Calldata

Run the wiring task for each chain you want to wire:

```bash
# Source chain only
npx hardhat custom:wire --token pufETH --dest megaeth --source-only

# Destination chain only
npx hardhat custom:wire --token pufETH --dest megaeth --dest-only

# Or both at once
npx hardhat custom:wire --token pufETH --dest megaeth
```

Each invocation produces a Safe batch JSON containing all 4 transactions for that chain:

- `.wiring-state/safe-batch-<source>-<token>.json` — on `<source>`, targets the OFTAdapter and the source EndpointV2
- `.wiring-state/safe-batch-<dest>-<token>.json` — on `<dest>`, targets the OFT and the destination EndpointV2

### Step 2: Execute via Safe Multisig

For each generated batch:

1. Import the Safe batch JSON into the Safe wallet on the matching chain
2. Collect signatures and execute the transactions
3. **Wait for the transactions to confirm on-chain** before executing the batch on the other chain (the `setSendConfig` / `setReceiveConfig` calls need the peer to already be set)

### Step 3: Verify Wiring

Check that both sides are properly configured:

```bash
npx hardhat custom:check --token pufETH --dest megaeth
```

This verifies that peers are set correctly on both chains.

## Contract Verification

Verify a deployed contract:

```bash
npx hardhat verify --network megaeth --contract contracts/pufETH.sol:pufETH <ADDRESS> <CONSTRUCTOR_ARGS>
```

Example:

```bash
npx hardhat verify --network megaeth --contract contracts/pufETH.sol:pufETH \
  0x37D6382B6889cCeF8d6871A8b60E667115eDDBcF \
  0x6F475642a6e85809B1c36Fa62763669b1b48DD5B \
  0x1BfAec64abFddcC8c5dA134880d1E71f3E03689E
```

## Using the Bridge

After wiring is complete, use the send task to transfer tokens:

```bash
npx hardhat send --network ethereum-mainnet --to <RECIPIENT> --amount <AMOUNT>
```

Don't forget to add the deployed contract address to ACL.

## Resources

- **LayerZero Deployment Addresses**: https://metadata.layerzero-api.com/v1/metadata/deployments
- **LayerZero Docs**: https://docs.layerzero.network/
- **LayerZero Scan** (cross-chain explorer): https://layerzeroscan.com/
