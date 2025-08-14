## Clone the repository
```bash
git clone https://github.com/PufferFinance/layerzero-bridge-scripts.git
```

## 1) Developing Contracts

### Installing Dependencies

We recommend using `pnpm` as the package manager (though you can use any package manager of your choice):

If you don't have pnpm installed, install it first:
```bash
curl -fsSL https://get.pnpm.io/install.sh | sh -
```

```bash
cd layerzero-bridge-scripts
```

```bash
pnpm install
```

### Setting Up a New Chain

#### Adding a New Contract for Bridging
1. Add the contract to `contracts/`
2. Update the token address in `deploy/MyOFTAdapter.ts`:
```typescript
args: [
    '0x<BASE_TOKEN_ADDRESS>', // The base token address
    endpointV2Deployment.address, // LayerZero's EndpointV2 address
    deployer, // Owner
],
```

#### Adding a New Chain for Bridging
1. Add the chain information to `hardhat.config.ts`
2. Add the chain mappings to `<TOKEN_NAME>.simple.config.ts`

### Compiling Your Contracts

This project supports both `hardhat` and `forge` compilation. By default, the `compile` command executes both:

```bash
pnpm compile
```

If you prefer one tool over the other, you can use the tool-specific commands:

```bash
pnpm compile:forge
pnpm compile:hardhat
```

Alternatively, you can modify the `package.json` to use only one build tool. For example, to remove `forge` build:

```diff
- "compile": "$npm_execpath run compile:forge && $npm_execpath run compile:hardhat",
- "compile:forge": "forge build",
- "compile:hardhat": "hardhat compile",
+ "compile": "hardhat compile"
```

### Deploying the Contracts

```bash
npx hardhat lz:deploy
```

You will be presented with a list of networks to deploy to. Make sure to fund your deployer account with native gas tokens beforehand.

**Important Note for Multisig Owners:**

If the contract owner is a multisig wallet (not an EOA), follow these steps:

1. **Generate Transaction Calldatas**: Run the `wire` script below to generate transaction calldatas. On new chains, the deployer becomes the owner, so all transactions can be executed directly via CLI. Only Mainnet transactions need to be executed through a safe.

2. **Execute Safe Transactions**: Create safe transactions with the generated calldatas that include the OmniAddress as the OFT address. You'll need 2 transactions:
   - `SetPeer`
   - `SetEnforcedOptionSet` on the Adapter
   
   Example: [Etherscan Transaction](https://etherscan.io/tx/0xce4f5d71219bcd4b0ba847fb02a611f82503a48ddbedba5b93e392cd2ef72b14#eventlog)

3. **Wire the Contracts**: After the safe transactions are executed, run the `wire` script again to configure the contracts and set up DVNs (this can be called by anyone).

4. **Verify Connections**: Run the `peers:get` script to verify the connections are properly established.

### Wiring the Contracts

Run the following command to wire the contracts:
```bash
npx hardhat lz:oapp:wire --oapp-config <TOKEN_NAME>.simple.config.ts
```

### Verifying the Connections

Run this command to verify the connections:
```bash
npx hardhat lz:oapp:peers:get --oapp-config <TOKEN_NAME>.simple.config.ts
```

## 2) Using the Bridge

After deploying the contracts, you can use the bridge to transfer tokens between chains. The project includes scripts for bridging tokens between Ethereum and BSC.

### Updating Script Values

The `scripts/BridgeToBSC.s.sol` and `scripts/BridgeToETH.s.sol` files contain the bridging scripts. You need to update the following parameters:

```solidity
// ---------- TO CHANGE ----------
address toAddress = 0x37f49eBf12c9dC8459A313E65c48aF199550159a; // Recipient address
uint256 _tokensToSend = 100 ether; // Amount to send (you can use decimal notation like 1.2 ether)
// ---------- TO CHANGE ----------
```

### Bridging Tokens

#### Bridge from Ethereum to BSC
```bash
pnpm bridge:to:bsc
```
This will generate a `cast` command. Copy and execute this command to perform the bridge transaction.

#### Bridge from BSC to Ethereum
```bash
pnpm bridge:to:eth
```
This will generate a `cast` command. Copy and execute this command to perform the bridge transaction.

**Prerequisites:**
- Sufficient tokens in your wallet on the source chain
- Sufficient native tokens for gas fees
- **Token spending approval for the bridge contract**

### Customizing Bridge Parameters

You can modify the following parameters in the bridge scripts:
- `toAddress`: The recipient address on the destination chain
- `_tokensToSend`: The amount of tokens to send (in ether units, e.g., "100 ether")

These parameters are located in `scripts/BridgeToBSC.s.sol` and `scripts/BridgeToETH.s.sol`.

<br></br>

<p align="center">
  Join our <a href="https://layerzero.network/community" style="color: #a77dff">community</a>! | Follow us on <a href="https://x.com/LayerZero_Labs" style="color: #a77dff">X (formerly Twitter)</a>
</p>
