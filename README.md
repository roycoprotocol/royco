# Royco: The Incentivized Action Market Protocol [![Tests](https://github.com/roycoprotocol/royco/actions/workflows/test.yml/badge.svg)](https://github.com/roycoprotocol/royco/actions/workflows/test.yml)
![Royco Banner](./roycobanner.png)

Royco Protocol allows anyone to create a market to incentivize any onchain transaction or series of transactions–we call these markets Incentivized Action Markets (IAMs).
In IAMs, Incentive Providers (IPs) offer incentives, like tokens or points, for Action Providers (APs) to perform onchain actions. IPs and APs make offers/counter-offers until they agree upon an incentive amount for which the AP will complete the transaction. When they agree, the AP’s transactions are programmatically executed and the incentives are atomically allocated to the AP.

There are two types of IAMs:

1. **Vault IAM**: Incentive Providers offer incentives to deposit into an underlying ERC4626 Vault.
2. **Recipe IAM**:  Incentive Providers offer incentives to perform any onchain transaction or series of transactions–aka a “recipe.”

Both are highly capital-efficient since APs can make offers with assets currently deployed in incentivized Vault IAMs, or other ERC4626 vaults.

Royco Protocol is entirely non-custodial, trustless, and permissionless. The following documentation details its smart contracts for developers who wish to interact with and build upon it. 

## Vault IAMs
A Vault IAM is a market that incentivizes deposits into an underlying 4626 Vault. To achieve this, there are two components:

**A. Wrapped Vault**: wraps an existing ERC-4626 Vault to distribute incentives to depositors.

**B. Vault Market**: enables APs and IPs to create offers for incentives and deposits.
### WrappedVault.sol
The Wrapped Vault wraps an existing ERC-4626 Vault to distribute incentives to APs who deposit into the underlying Vault.

Anyone can use the Wrapped Vault Factory to point to an ERC-4626 Vault and specify what incentives will be distributed (up to 20 different assets) and an owner address (i.e. an EOA, contract, many party multi-sig, etc.) that the incentives will be contributed from. The owner can also "extend" incentive campaigns by calling extendRewardsInterval, as long as the new offered rewards rate is higher than or equal to the current rewards rate. The underlying Vault must be fully compliant to ERC-4626 behavior.

Once the Wrapped Vault is deployed, IPs can distribute pro-rata, pool-style incentives to APs who enter the underlying 4626 Vault through the Vault Market.

### VaultMarketHub.sol
A Vault Market enables IPs and APs to negotiate for the incentives required to deposit into the underlying ERC-4626 Vault. APs can make conditional offers specifying the incentive they would need to receive per deposit token, in offer to deposit into the Vault. For example, “10 $ABC per 1 USDC” or “1 ABC Points per 1 ETH.” APs make these offers via approvals, so they can make an unlimited number of conditional offers with the same ERC20 tokens as collateral. 

An IP could see these conditional offers, update their incentive rates to meet them, and call allocateOffer to draw all in-range offers into the Vault (as long as the incentive campaign has a minimum remaining duration of 1 week. Following this, the streaming rates will continue to fluctuate as incentives are added and APs enter/exit the Vault.

**AP Capital Efficiency:** AP Offers are placed via approvals so APs can make an unlimited number of offers with the same ERC20 tokens in their wallet–but also with tokens currently deployed in other 4626 Vaults. If an AP’s conditional offer is filled by an IP, they are automatically allocated from their current Vault and deposited into another Vault.

## Recipe IAMs
A Recipe IAM is a market that can incentivize any arbitrary onchain transaction or series of transactions that an EOA can perform. Recipe IAMs achieve this through the scripting language, [Weiroll](https://github.com/weiroll/weiroll). Weiroll allows Market Creators to define single transactions or complex, operation-chaining “recipes” of transactions for IPs to incentivize. There are two components,

**A. Weiroll Wallet**: wraps an existing ERC-4626 Vault to distribute incentives to depositors.

**B. Recipe Market**: enables APs and IPs to create offers for incentives and deposits.

### WeirollWallet.sol
In Recipe IAMs, when an AP makes an offer, they transfer their funds into a fully self-custodial, lightweight, disposable smart contract wallet with Weiroll VM built-in. The AP uses this wallet to execute Weiroll scripts and limit the funds exposed in each transaction.

IPs may want to ensure that an AP performs the defined action (e.g. hold a position) for some set amount of time. So for these markets, IPs can specify that the AP must deploy a Weiroll Wallet with a pre-defined timelock. After the timelock expires, the AP may call a withdrawal recipe specified in the market, or can simply pass raw call data for the wallet to execute.

### RecipeMarketHub.sol
Like a Vault Market, a Recipe Market enables IPs and APs to negotiate for incentives, but it also enables Incentive Providers to create conditional offers. For example, as an IP I will pay you, “1 USDC for calling the Weiroll Recipe with $10 ABC.” IPs and APs can effectively offer/counter-offer to find the true price of the Weiroll Recipe execution

## Other Contracts

### WrappedVaultFactory.sol
A factory contract for spinning up new wrapped vaults, and tracking the current protocol fee and frontend fee.

### Points.sol
An ERC20-like contract which has no state which could be tokenized, but rather simply awards APs points via events. Points award functions are highly restricted to prevent anyone from awarding points arbitrarily.

### PointsFactory.sol
A factory contract for spinning up new points campaigns, keeps a mapping of points programs for market hubs to quickly decide if an address belongs to a token or a points campaign.

## Getting started
Royco is built using [Foundry](https://github.com/foundry-rs/foundry)

**Installing Dependencies** ``` forge install ```

**Running Tests:** ``` forge test ```

## Deployments
Royco was initially deployed to Ethereum Mainnet, Arbitrum, and Base at the following deterministic deployment addresses:

**PointsFactory:**
0x19112AdBDAfB465ddF0b57eCC07E68110Ad09c50

**WrappedVaultFactory:**
0x75E502644284eDf34421f9c355D75DB79e343Bca

**VaultMarketHub:**
0xa97eCc6Bfda40baf2fdd096dD33e88bd8e769280

**WeirollWallet:**
0x40a1c08084671E9A799B73853E82308225309Dc0

**RecipeMarketHub:**
0x783251f103555068c1E9D755f69458f39eD937c0
