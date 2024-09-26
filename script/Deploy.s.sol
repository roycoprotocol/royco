// SPDX-License-Identifier: UNLICENSED

// Usage: source .env && forge script ./script/Deploy.s.sol --rpc-url=$SEPOLIA_RPC_URL --broadcast --etherscan-api-key=$ETHERSCAN_API_KEY --verify

pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {ERC4626i} from "../src/ERC4626i.sol";
import {ERC4626iFactory} from "../src/ERC4626iFactory.sol";
import {Points} from "../src/Points.sol";
import {PointsFactory} from"../src/PointsFactory.sol";
import {VaultOrderbook} from "../src/VaultOrderbook.sol";
import {RecipeOrderbook} from "../src/RecipeOrderbook.sol";
import {WeirollWallet} from "../src/WeirollWallet.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        PointsFactory pointsFactory = new PointsFactory(deployerAddress);
        ERC4626iFactory erc4626iFactory = new ERC4626iFactory(deployerAddress, 0.01e18, 0.001e18, address(pointsFactory) );

        WeirollWallet wwi = new WeirollWallet();
        VaultOrderbook orderbook = new VaultOrderbook();
        RecipeOrderbook recipeOrderbook = new RecipeOrderbook(
            address(wwi),
            0.01e18, // 1% protocol fee
            0.001e18, // 0.1% minimum frontend fee
            msg.sender,
            address(pointsFactory)
        );

        // ERC20 underlyingToken = ERC20(address(new MockERC20("Mock Token", "MOCK")));
        // ERC4626 testVault = ERC4626(address(new MockERC4626(underlyingToken)));

        vm.stopBroadcast();
    }
}