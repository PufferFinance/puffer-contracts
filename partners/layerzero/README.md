## Clone the repository
```bash
git clone https://github.com/PufferFinance/layerzero-bridge-scripts.git
```

## 1) Developing Contracts

#### Installing dependencies

We recommend using `pnpm` as a package manager (but you can of course use a package manager of your choice):

Install pnpm if you don't have it already:
```bash
curl -fsSL https://get.pnpm.io/install.sh | sh -
```

```bash
cd layerzero-bridge-scripts
```

```bash
pnpm install
```

### Seting up the new chain

#### If adding a new contract for bridging:
1. Add the contract to `contracts/`
2. Update the token address in `deploy/MyOFTAdapter.ts`   
```
args: [
    '0x<BASE_TOKEN_ADDRESS>', // the basetoken address
    endpointV2Deployment.address, // LayerZero's EndpointV2 address
    deployer, // owner
],
```

#### If adding a new chain for bridging:
 1. Add the chain info to `hardhat.config.ts`
 2. Add the chain mappings to `<TOKEN_NAME>.simple.config.ts`

#### Compiling your contracts

This project supports both `hardhat` and `forge` compilation. By default, the `compile` command will execute both:

```bash
pnpm compile
```

If you prefer one over the other, you can use the tooling-specific commands:

```bash
pnpm compile:forge
pnpm compile:hardhat
```

Or adjust the `package.json` to for example remove `forge` build:

```diff
- "compile": "$npm_execpath run compile:forge && $npm_execpath run compile:hardhat",
- "compile:forge": "forge build",
- "compile:hardhat": "hardhat compile",
+ "compile": "hardhat compile"
```

### Deploying the contracts

```bash
npx hardhat lz:deploy   n    # choose the network you want to deploy to
```

You will be presented with a list of networks to deploy to.

Fund your deployer with native gas tokens beforehand.

#### Wire the contracts

Run the following command to wire the contracts:
```bash
npx hardhat lz:oapp:wire --oapp-config <TOKEN_NAME>.simple.config.ts
```

#### Verify the connections

Run to verify the connections:
```bash
npx hardhat lz:oapp:peers:get --oapp-config <TOKEN_NAME>.simple.config.ts
```

## 3) Using the Bridge

After deploying the contracts, you can use the bridge to transfer tokens between chains. The project includes scripts for bridging tokens between Ethereum and BSC.

### Update the values in the scripts

The `scripts/BridgeToBSC.s.sol` and `scripts/BridgeToETH.s.sol` files contain the script for bridging tokens between Ethereum and BSC.
You need to update:
```       
// ----------TO CHANGE----------
        address toAddress = 0x37f49eBf12c9dC8459A313E65c48aF199550159a; //recipient address
        uint256 _tokensToSend = 100 ether; //amount to send; you can also decimal ether like 1.2 ether
// ----------TO CHANGE----------
```

### Bridging Tokens

1. To bridge tokens from Ethereum to BSC:
```bash
pnpm bridge:to:bsc
```
This will generate a `cast` command. Copy and execute this command to perform the bridge transaction.

2. To bridge tokens from BSC to Ethereum:
```bash
pnpm bridge:to:eth
```
This will generate a `cast` command. Copy and execute this command to perform the bridge transaction.

Note: Make sure you have:
- Sufficient tokens in your wallet on the source chain
- Sufficient native tokens for gas fees
- **Approved the token spending for the bridge contract**

### Customizing Bridge Parameters

You can modify the following parameters in the bridge scripts:
- `toAddress`: The recipient address on the destination chain
- `_tokensToSend`: The amount of tokens to send (in ether units, e.g., "100 ether")

These parameters can be found in `scripts/BridgeToBSC.s.sol` and `scripts/BridgeToETH.s.sol`.

<br></br>

<p align="center">
  Join our <a href="https://layerzero.network/community" style="color: #a77dff">community</a>! | Follow us on <a href="https://x.com/LayerZero_Labs" style="color: #a77dff">X (formerly Twitter)</a>
</p>
