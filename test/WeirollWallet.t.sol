// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// // Smart wallet contracts
// import { WeirollWallet } from "src/WeirollWallet.sol";
// import { WalletFactory } from "src/WalletFactory.sol";

// // Testing contracts
// import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

// contract WeirollWalletTest is DSTestPlus {
//     ExampleFactory public factory;

//     function setUp() public {
//         factory = new ExampleFactory();
//     }

//     function testWalletCreation() public {
//         factory.createWallet(address(this), address(0));
//         assert(address(factory).code.length > 0);
//     }

//     function testWalletVariablesSet() public {
//         WeirollWallet wallet = WeirollWallet(factory.createWallet(address(0x01), address(this)));
//         assertEq(wallet.getOwner(), address(0x01));
//         assertEq(wallet.getOrderbook(), address(this));
//     }
// }

// // Example Factory for deploying wallet implementation clowns
// contract ExampleFactory is WalletFactory {
//     constructor() WalletFactory(address(new WeirollWallet())) { }

//     function createWallet(address owner, address orderbook) public returns (address) {
//         return address(deployClone(owner, orderbook));
//     }
// }
