// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ClonesWithImmutableArgs } from "../lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { WeirollWallet } from "./WeirollWallet.sol";

contract WalletFactory {
    using ClonesWithImmutableArgs for address;

    // Implementation contract address
    // todo: should this be immutable?
    address public immutable implementation;

    // Set the implementation address
    constructor(address implementation_) {
        implementation = implementation_;
    }

    // Deploy a proxy for the wallet implementation contract
    // @param owner The owner of the wallet (address of the IP or LP)
    // @param orderbook The address of the orderbook
    // @param unlockTime The nonce of the wallet
    function deployClone(
        address owner,
        address orderbook
    )
        // uint256 unlockTime
        internal
        returns (WeirollWallet clone)
    {
        // the second parameter is the address of the of the orderbook
        bytes memory data = abi.encodePacked(owner, orderbook);
        clone = WeirollWallet(implementation.clone(data));
    }
}
