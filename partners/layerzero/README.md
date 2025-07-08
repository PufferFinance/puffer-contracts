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
