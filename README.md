# Royco: The Incentivized Action Market Protocol
![Royco Banner](./roycobanner.png)

Royco allows anyone to create a market around any onchain action. Those who wish to pay to execute an onchain action are called "Incentive Providers" (IPs) and offer token or points incentives in exchange for an "Action Provider" (APs) to take some action, be it enter a staking vault, or execute some "recipe" of one or more smart contract interactions, each having their own market types on Royco.

## Vault Markets
Actions which deposit in staking vaults are called "Vault Markets". Vault Markets consist of a Royco wrapped vault and a Vault Market Hub.
### WrappedVault.sol
Vault Markets are centered around wrapped vaults, which are 4626 vaults wrapped with the ability to stream "incentives". Wrapped vaults are created through the WrappedVaultFactory by simply pointing to an existing 4626 vault and deploying a new WrappedVault to allow IPs to distribute Unipool style staking incentives to APs who deposit in the vault through the wrapper. The underlying 4626 vault must be fully compliant to vanilla 4626 behavior, meaning working previewWithdraw functions, immediate deposits/withdrawals, etc.

Wrapped vaults are owned by the Incentive Provider who deploys them. The IP who owns a wrapped vault is solely permissioned to distribute incentives, and may add additional incentive tokens or points campaigns at any time, (for up to 20 different assets). IPs can also "extend" incentive campaigns by calling extendRewardsInterval, however to prevent dishonest AP limit offer sniping, IPs must keep the new rewards rate equivalent or higher than the current rewards rate when doing so.

### VaultMarketHub.sol
The Vault Market Hub is where APs offer to deposit into wrapped vaults. APs place "limit offers" on vaults specifying the incentive rates they would need to receive per deposit token in offer to be allocated into a vault. Once a vault is streaming the rate desired by the LP, an IP can call allocateOffer to draw the in-range offers into the pool.

Offers on Royco's Vault Market Hub are placed without transferring tokens to the hub, allowing many offers to be placed off of the same tokens. Additionally, offers can be placed against not only ERC20 tokens but also against other 4626 or wrapped vaults, withdrawing from the vaults on offer fill to allow APs to farm one pool while simultaneously offering to enter other pools if incentive rates increase.

## Recipe Markets
More long-tail actions which may not be easily represented by 4626 vaults instead occur through recipe markets, which heavily rely on the [operation-chaining/scripting language Weiroll](https://github.com/weiroll/weiroll). Weiroll allows IPs to write complex chained "Recipes" of smart contract interactions that can express any chain of actions you could make through an EOA.

### WeirollWallet.sol
Instead of depositing in a wrapped vault, recipe markets deposit assets into a lightweight, disposable, smart contract wallet owned by the AP with the Weiroll VM built in. This allows the AP to execute weiroll scripts without exposing all their funds to the arbitrary (and potentially malicious) interactions given by the script. Weiroll Wallets also allow locking the wallet itself, enabling IPs to ensure an AP holds their position after executing the script for some set amount of time. 

After a timelock has expired, an AP gains full control over the wallet, and is now able to call a withdrawal recipe specified in the market, or can simply pass raw calldata for the wallet to execute.

### RecipeMarketHub.sol
The Recipe Market Hub functions much like the Vault Market Hub, but allows Incentive Providers to also place limit offers, stating that they are willing to pay APs some amount of incentive in exchange for calling the Weiroll recipe with some amount of deposit token. Both IP and AP limit offers may be filled by the opposite parties.

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
