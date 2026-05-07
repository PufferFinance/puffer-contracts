# Chainlink CCIP — Puffer Cross-Chain Token (CCT) integration

Foundry project that wires `pufETH` / `xPufETH` into Chainlink CCIP. It contains the scripts used to deploy token pools, register them in the `TokenAdminRegistry`, configure remote chains and rate limits, and run end-to-end test transfers.

The on-chain "lock-and-mint" model used here is:

- **Ethereum mainnet**: `pufETH` is wrapped by a `LockReleaseTokenPool`. Tokens going outbound are *locked* in the pool; tokens coming inbound are *released*.
- **Every other chain** (Arbitrum, Berachain, Soneium, Zircuit, …): `xPufETH` is paired with a `BurnMint` / `BurnWithFromMint` token pool. Outbound transfers *burn* `xPufETH`; inbound transfers *mint* it.

## Layout

```
partners/chainlink/
├── foundry.toml                 # solc 0.8.24, fs read-write under ./
├── src/Dependencies.sol         # forces compilation of vendored CCIP contracts
└── script/
    ├── HelperConfig.s.sol       # per-chain CCIP addresses + chainSelectors
    ├── utils/HelperUtils.s.sol  # JSON / chainId helpers
    ├── config.json              # operator inputs (token metadata, amounts, remote-chain map)
    ├── output/                  # script outputs — deployment registry (committed)
    │   ├── deployedToken_<chain>.json
    │   ├── deployedTokenPool_<chain>.json
    │   └── chainUpdatesMainnet_<remote>.json   # Safe-ready JSON for ApplyChainUpdates on mainnet
    ├── DeployToken.s.sol
    ├── DeployBurnMintTokenPool.s.sol
    ├── DeployBurnWithFromMintTokenPool.s.sol
    ├── DeployLockReleaseTokenPool.s.sol
    ├── ClaimAdmin.s.sol            # registryModuleOwnerCustom path (deployer is also tokenOwner)
    ├── AcceptAdminRole.s.sol       # finishes a self-claim
    ├── TransferTokenAdminRole.s.sol  # propose new admin (e.g. multisig)
    ├── AcceptTokenAdminRole.s.sol    # multisig accepts the proposed admin role
    ├── SetPool.s.sol               # registers pool for token in TokenAdminRegistry
    ├── ApplyChainUpdates.s.sol     # broadcasts pool.applyChainUpdates directly
    ├── ApplyChainUpdatesMainnet.s.sol  # generates Safe-ready calldata instead of broadcasting
    ├── AddRemotePool.s.sol
    ├── RemoveRemotePool.s.sol
    ├── UpdateRateLimiters.s.sol
    ├── UpdateAllowList.s.sol
    ├── SetRateLimitAdmin.s.sol
    ├── GetCurrentRateLimits.s.sol  # read-only
    ├── GetPoolConfig.s.sol         # read-only
    ├── MintTokens.s.sol            # mint test xPufETH (only on chains where deployer mints)
    └── TransferTokens.s.sol        # send a CCIP message via the Router (test transfers)
```

## Supported chains

| Chain | chainId | `chainSelector` | Helper key |
|---|---:|---:|---|
| Ethereum mainnet | 1 | 5009297550715157269 | `getEthereumConfig` |
| Arbitrum | 42161 | 4949039107694359620 | `getArbitrumConfig` |
| Berachain | 80094 | 1294465214383781161 | `getBerachainConfig` |
| Soneium | 1868 | 12505351618335765396 | `getSoneiumConfig` |
| Zircuit | 48900 | 17198166215261833993 | `getZircuitConfig` |
| Ethereum Sepolia | 11155111 | 16015286601757825753 | `getEthereumSepoliaConfig` |
| Arbitrum Sepolia | 421614 | — | `getArbitrumSepolia` |
| Avalanche Fuji | 43113 | — | `getAvalancheFujiConfig` |
| Base Sepolia | 84532 | — | `getBaseSepoliaConfig` |

Adding a new chain means:
1. Add a `getXxxConfig()` to [script/HelperConfig.s.sol](script/HelperConfig.s.sol) and a `chainid` branch in its constructor.
2. Add the same `chainid` branches to `getChainName` / `getNetworkConfig` in [script/utils/HelperUtils.s.sol](script/utils/HelperUtils.s.sol).
3. Drop a `script/output/deployedToken_<chain>.json` (or run `DeployToken` to create one).

## Configuration: `script/config.json`

```jsonc
{
  "BnMToken": {                          // metadata when deploying a fresh xPufETH
    "name": "pufETH",
    "symbol": "pufETH",
    "decimals": 18,
    "maxSupply": 0,                      // 0 = unlimited
    "withGetCCIPAdmin": false,           // ClaimAdmin path: false = use owner()
    "ccipAdminAddress": "0x0000…0000"
  },
  "tokenAmountToMint": 1000000000000000000000,
  "tokenAmountToTransfer": 10000,
  "feeType": "native",                   // "native" | "link"
  "remoteChains": {                      // sourceChainId -> destinationChainId for TransferTokens / ApplyChainUpdates*
    "1868": 1,
    "42161": 1,
    "80094": 1,
    "1": 80094
  }
}
```

The `remoteChains` map is **1-to-1**: each source chain has exactly one destination at a time. To test a different lane (e.g. Eth ↔ Zircuit), edit the entry for chainId `1` (and add `"48900": 1` for the return leg) before running the script.

The deployment registry under [script/output/](script/output/) is committed: every successful run rewrites the `deployedToken_<chain>.json` / `deployedTokenPool_<chain>.json` it produced, and downstream scripts read from there.

## Onboarding a new chain — end-to-end

The flow assumes pufETH already exists on Ethereum and we're adding chain `X`. Where the script broadcasts on-chain, prefix with `--rpc-url $X_RPC_URL --account <signer> --broadcast`. Where governance is required (mainnet pool ops, registry ops on chains where the admin is a multisig), use the `*Mainnet` variant or build calldata with `cast` and feed it through the Safe / RBACTimelock.

### 1. Token

If `xPufETH` is already deployed on chain X, just write `script/output/deployedToken_<chain>.json`:

```json
{ "deployedToken_<chain>": "0xExistingTokenAddress" }
```

Otherwise:

```bash
forge script script/DeployToken.s.sol --rpc-url $X_RPC_URL --account <deployer> --broadcast
```

### 2. Pool

Pick the pool type that matches the token model on this chain:

- **Mainnet (lock/release `pufETH`)**: `DeployLockReleaseTokenPool.s.sol`
- **Burn-and-mint `xPufETH`** (token has `mint(address,uint256)`): `DeployBurnMintTokenPool.s.sol`
- **Burn-from / mint `xPufETH`** (token has `burnFrom(address,uint256)`): `DeployBurnWithFromMintTokenPool.s.sol`

```bash
forge script script/DeployBurnWithFromMintTokenPool.s.sol --rpc-url $X_RPC_URL --account <deployer> --broadcast
```

The pool address is written to `script/output/deployedTokenPool_<chain>.json`.

### 3. Register the token administrator in `TokenAdminRegistry`

Two paths, depending on who controls the token:

**a) Self-service (deployer == token owner / has CCIP admin):**

```bash
forge script script/ClaimAdmin.s.sol         --rpc-url $X_RPC_URL --account <admin> --broadcast
forge script script/AcceptAdminRole.s.sol    --rpc-url $X_RPC_URL --account <admin> --broadcast
```

**b) Hand-off to a multisig** (e.g. transfer admin from the deployer EOA to the Operations Multisig — same flow used for Zircuit):

```bash
# 1. Current admin proposes the new admin (broadcasts a TokenAdminRegistry.transferAdminRole tx)
forge script script/TransferTokenAdminRole.s.sol --rpc-url $X_RPC_URL --account <current-admin> --broadcast

# 2. The proposed admin (multisig) accepts.
forge script script/AcceptTokenAdminRole.s.sol  --rpc-url $X_RPC_URL --account <multisig-signer> --broadcast
# Or build calldata for the Safe:
#   cast calldata "acceptAdminRole(address)" <token>
#   target = TokenAdminRegistry (see HelperConfig)
```

Verify with `cast`:
```bash
cast call <TokenAdminRegistry> "getTokenConfig(address)((address,address,bool))" <token> --rpc-url $X_RPC_URL
# tuple = (administrator, pendingAdministrator, isRegistered)
```

### 4. Register the pool

Once the admin is accepted, the admin (EOA or multisig) calls `setPool`:

```bash
forge script script/SetPool.s.sol --rpc-url $X_RPC_URL --account <admin> --broadcast
```

If admin is a multisig, build the calldata: `cast calldata "setPool(address,address)" <token> <pool>` and propose it via Safe.

### 5. Wire the pool to remote chains

Each pool needs to know about every remote chain it talks to (its `remoteChainSelector`, the remote pool, and the remote token). On non-mainnet chains where the deployer still controls the pool:

```bash
forge script script/ApplyChainUpdates.s.sol --rpc-url $X_RPC_URL --account <pool-owner> --broadcast
```

**On Ethereum mainnet, the pool is owned by a Safe/timelock**, so use the calldata generator instead — it writes a Safe-ready transaction file:

```bash
forge script script/ApplyChainUpdatesMainnet.s.sol --rpc-url $MAINNET_RPC_URL
# -> script/output/chainUpdatesMainnet_<remote>.json (upload to Safe / Den)
```

Both scripts use `remoteChains[<currentChainId>]` from `config.json` to pick the *one* remote being added — repeat the run with different entries to wire multiple remotes.

For incremental edits later, [AddRemotePool](script/AddRemotePool.s.sol) / [RemoveRemotePool](script/RemoveRemotePool.s.sol) modify a single chain's remote-pool list without touching anything else.

### 6. (Optional) Rate limits and allow list

```bash
forge script script/UpdateRateLimiters.s.sol --rpc-url $X_RPC_URL --account <pool-owner> --broadcast
forge script script/UpdateAllowList.s.sol    --rpc-url $X_RPC_URL --account <pool-owner> --broadcast
forge script script/SetRateLimitAdmin.s.sol  --rpc-url $X_RPC_URL --account <pool-owner> --broadcast
```

Read-only checks:

```bash
forge script script/GetCurrentRateLimits.s.sol --rpc-url $X_RPC_URL
forge script script/GetPoolConfig.s.sol        --rpc-url $X_RPC_URL
```

## Test transfers

After all the above is in place on **both** sides of a lane:

1. Set `config.json → remoteChains` to point the source chain at the destination you want.
2. Top up the sender with the source-chain token and a bit of native gas.
3. Run the script on each chain:

```bash
# Ethereum -> remote
forge script script/TransferTokens.s.sol --rpc-url $MAINNET_RPC_URL --account <sender> --broadcast
# remote -> Ethereum
forge script script/TransferTokens.s.sol --rpc-url $X_RPC_URL --account <sender> --broadcast
```

The script logs the `messageId` and a `https://ccip.chain.link/msg/<id>` URL.

### Sending CCIP messages manually with `cast`

If you'd rather not use the script (e.g. to control the sender or experiment with extra args), the equivalent is two calls — `approve` then `ccipSend`:

```bash
ROUTER=<chain CCIP Router>
TOKEN=<source token>
DEST_SELECTOR=<destination chainSelector>
RECIPIENT=<your address>
AMOUNT=10000
RECEIVER_ENC=$(cast abi-encode "f(address)" $RECIPIENT)

# CCIP EVMExtraArgsV2: tag || abi.encode(uint256 gasLimit, bool allowOutOfOrderExecution)
EXTRA_ARGS=0x181dcf10$(cast abi-encode "f(uint256,bool)" 0 true | sed 's/^0x//')

FEE=$(cast call $ROUTER \
  "getFee(uint64,(bytes,bytes,(address,uint256)[],address,bytes))(uint256)" \
  $DEST_SELECTOR \
  "($RECEIVER_ENC,0x,[($TOKEN,$AMOUNT)],0x0000000000000000000000000000000000000000,$EXTRA_ARGS)" \
  --rpc-url $RPC)

cast send $TOKEN  "approve(address,uint256)" $ROUTER $AMOUNT --rpc-url $RPC --account <sender>
cast send $ROUTER \
  "ccipSend(uint64,(bytes,bytes,(address,uint256)[],address,bytes))(bytes32)" \
  $DEST_SELECTOR \
  "($RECEIVER_ENC,0x,[($TOKEN,$AMOUNT)],0x0000000000000000000000000000000000000000,$EXTRA_ARGS)" \
  --value $FEE \
  --gas-limit 500000 \
  --rpc-url $RPC --account <sender>
```

Replace the `feeToken` (4th tuple field) with the chain's LINK address and drop `--value` to pay fees in LINK instead.

> Heads-up: [TransferTokens.s.sol](script/TransferTokens.s.sol) currently builds **EVMExtraArgsV1**. Most active CCIP lanes (including Zircuit) require **V2** with `allowOutOfOrderExecution=true` and revert with `ExtraArgOutOfOrderExecutionMustBeTrue()` against V1. The script needs a small update; the `cast` snippet above already uses V2.

## Common revert selectors

| Selector | Meaning |
|---|---|
| `0xee433e99` | `ExtraArgOutOfOrderExecutionMustBeTrue()` — use EVMExtraArgsV2 with `allowOutOfOrderExecution=true` |
| `0x07da6ee6` | `InsufficientFeeTokenAmount()` — fee drifted; re-quote `getFee` and resend |
| `0xfb8f41b2` | `ERC20InsufficientAllowance(spender, allowance, needed)` — call `approve` on the source token first |

## Toolchain

```bash
forge build       # compile (solc 0.8.24)
forge test        # there are no project tests — Chainlink CCIP is the dependency under test
forge fmt
```

Dependencies are pulled via `pnpm` (lockfile committed). The `@chainlink/contracts-ccip/` and `forge-std/` remappings in [foundry.toml](foundry.toml) point at `node_modules/`.
