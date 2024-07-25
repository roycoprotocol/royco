// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Smart wallet contracts
import {Smartwallet} from "src/WeirollWalletImplementation.sol";
import {WalletFactory} from "src/WalletFactory.sol";

// Testing contracts
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract WeirollWalletTest is DSTestPlus {
    ExampleFactory public factory;

    function setUp() public {
        factory = new ExampleFactory();
    }

    function testWalletCreation() public {
        factory.createWallet(address(this), address(0), 0);
        assert(address(factory).code.length > 0);
    }

    function testWalletVariablesSet() public {
        Smartwallet wallet = Smartwallet(factory.createWallet(address(0x01), address(this), 256));
        assertEq(wallet.getOwner(), address(0x01));
        assertEq(wallet.getOrderbook(), address(this));
        assertEq(wallet.getUnlockTime(), 256);
    }
}

// Example Factory for deploying wallet implementation clowns
contract ExampleFactory is WalletFactory {
    constructor() WalletFactory(address(new Smartwallet())) {}

    function createWallet(address owner, address orderbook, uint256 unlockTime) public returns (address) {
        return address(deployClone(owner, orderbook, unlockTime));
    }
}