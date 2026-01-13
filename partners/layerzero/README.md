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
   - `PRIVATE_KEY` or `MNEMONIC` for transaction signing
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

Wire contracts between Ethereum (source) and a destination chain:

```bash
npx hardhat custom:wire --token pufETH --dest megaeth
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--token` | Token to wire (pufETH or PUFFER) | required |
| `--dest` | Destination chain name | required |
| `--source` | Source chain name | ethereum-mainnet |
| `--mode` | Execution mode: auto, execute, or calldata | auto |
| `--restart` | Ignore saved state and start fresh | false |
| `--dry-run` | Show what would be done without executing | false |
| `--source-only` | Only wire source chain | false |
| `--dest-only` | Only wire destination chain | false |
| `--skip-endpoint-config` | Skip EndpointV2 config (for multisig flows) | false |

### Execution Modes

- **auto** (default): Executes transactions if signer is owner, otherwise generates calldata
- **execute**: Always attempt to execute transactions
- **calldata**: Always generate calldata (useful for multisig)

### Resume Support

The wiring script saves state to `.wiring-state/` and can resume from where it left off. Use `--restart` to start fresh.

### Example: Wire to MegaETH

```bash
# Full wiring (both chains)
npx hardhat custom:wire --token pufETH --dest megaeth

# Only wire destination chain (if source already done via multisig)
npx hardhat custom:wire --token pufETH --dest megaeth --dest-only

# Dry run to see what would happen
npx hardhat custom:wire --token pufETH --dest megaeth --dry-run
```

## Checking Wiring Status

Verify that contracts are properly wired:

```bash
npx hardhat custom:check --token pufETH --dest megaeth
```

## Multisig Workflow

If the source chain contract (OFTAdapter) is owned by a multisig, follow these steps:

### Understanding the Wiring Process

The wiring process involves 4 transactions on each chain:

| # | Transaction | Contract | Who Can Execute |
|---|-------------|----------|-----------------|
| 1 | `setPeer` | OFTAdapter | Owner only (multisig) |
| 2 | `setEnforcedOptions` | OFTAdapter | Owner only (multisig) |
| 3 | `setSendConfig` | EndpointV2 | Delegate (set during deployment) |
| 4 | `setReceiveConfig` | EndpointV2 | Delegate (set during deployment) |

**Why we split these:**
- Transactions 1-2 modify the OFTAdapter contract and require the multisig owner to sign
- Transactions 3-4 are called on the LayerZero EndpointV2 contract and can be executed by the **delegate** (typically the deployer wallet)
- The EndpointV2 config calls may revert if the peer is not set yet, so they must be executed **after** the Safe transactions confirm

### Step 1: Generate Safe Calldata (OFT-level transactions only)

Use `--skip-endpoint-config` to generate calldata for only the multisig-required transactions:

```bash
npx hardhat custom:wire --token pufETH --dest megaeth --skip-endpoint-config --source-only
```

This generates calldata for only 2 transactions:
- `setPeer` - on pufETHAdapter (links to the destination chain OFT)
- `setEnforcedOptions` - on pufETHAdapter (sets minimum gas for cross-chain messages)

Calldata is saved to `.wiring-state/safe-batch-ethereum-mainnet-pufETH.json`

### Step 2: Execute via Safe Multisig

1. Import the Safe batch JSON into your Safe wallet
2. Execute the transactions
3. **Wait for the transactions to confirm on-chain**

### Step 3: Execute Endpoint Config via CLI (after Safe transactions confirm)

Once the peer is set via Safe, come back to the CLI and execute the EndpointV2 config. This is executed as a regular transaction from your deployer wallet (which has delegate permission):

```bash
npx hardhat custom:wire --token pufETH --dest megaeth --source-only
```

This will execute as direct transactions (not calldata):
- `setSendConfig` - on EndpointV2 (configures which DVNs verify outgoing messages)
- `setReceiveConfig` - on EndpointV2 (configures which DVNs verify incoming messages)

**Note:** The script will skip steps 1-2 if they're already completed (saved in `.wiring-state/`).

### Step 4: Wire the Destination Chain

Wire the destination chain. Since you deployed the OFT on the new chain, you are the owner and can execute all 4 transactions directly:

```bash
npx hardhat custom:wire --token pufETH --dest megaeth --dest-only
```

This executes all 4 transactions on the destination chain:
- `setPeer` - links back to Ethereum OFTAdapter
- `setEnforcedOptions` - sets minimum gas for messages to Ethereum
- `setSendConfig` - configures DVNs for outgoing messages
- `setReceiveConfig` - configures DVNs for incoming messages

### Step 5: Verify Wiring

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
