// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../src/ERC4626i.sol";
import "../src/ERC4626iFactory.sol";
import "../src/Points.sol";
import "../src/PointsFactory.sol";
import "../src/VaultOrderbook.sol";
import "../src/RecipeOrderbook.sol";
import "../src/WeirollWallet.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PointsFactory pointsFactory = new PointsFactory();
        ERC4626iFactory erc4626iFactory = new ERC4626iFactory(0.01e18, 0.001e18, address(pointsFactory) );
        WeirollWallet wwi = new WeirollWallet();
        VaultOrderbook orderbook = new VaultOrderbook();
        RecipeOrderbook recipeOrderbook = new RecipeOrderbook(
            address(wwi),
            0.01e18, // 1% protocol fee
            0.001e18, // 0.1% minimum frontend fee
            msg.sender,
            address(pointsFactory)
        );

        ERC20 underlyingToken = ERC20(address(new MockERC20("Mock Token", "MOCK")));
        ERC4626 testVault = ERC4626(address(new MockERC4626(underlyingToken)));
        ERC4626i iVault = erc4626iFactory.createIncentivizedVault(testVault);

        // points = factory.createPointsProgram("Test Points", "TP", 18, mockVault, mockOrderbook);

        vm.stopBroadcast();
    }
}
