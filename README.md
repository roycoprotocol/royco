# Royco
![Royco Banner](./RoycoBanner.png)
Royco allows anyone to create a market around any onchain action. Those who wish to pay users to execute an onchain action are called "Incentive Providers" and offer token or points incentives in exchange for an "Action Provider" to take some action, be it enter a staking vault, or execute some "recipe" of one or more smart contract interactions, each having their own market types on Royco.

## Vault Markets
Actions which deposit in staking vaults are called "Vault Markets". Vault Markets consist of a Royco 4626i Vault and a Royco Vault Orderbook
### ERC4626i.sol
(Owned, up to 5 incentive campaigns)

### VaultOrderbook.sol
(Orders placed in rates)

## Recipe Markets

### WeirollWallet.sol
(Uses a forked version of Weiroll with delegatecall removed)

### RecipeOrderbook.sol
(Orders placed in lump)
(Reward styles)

## Other Contracts

### ERC4626iFactory.sol

### Points.sol

### PointsFactory.sol