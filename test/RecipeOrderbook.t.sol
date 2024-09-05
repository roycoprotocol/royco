// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/RecipeOrderbook.sol";
import "../src/WeirollWallet.sol";
import "../src/PointsFactory.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import "lib/solmate/src/tokens/ERC20.sol";
import "lib/solmate/src/tokens/ERC4626.sol";

contract RecipeOrderbookTest is Test {
    RecipeOrderbook public orderbook;
    WeirollWallet public weirollWalletImplementation;
    MockERC20 public mockToken;
    MockERC4626 public mockVault;
    PointsFactory public pointsFactory;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        
        weirollWalletImplementation = new WeirollWallet();
        mockToken = new MockERC20("Mock Token", "MT");
        mockVault = new MockERC4626(mockToken);
        pointsFactory = new PointsFactory();
        
        
        orderbook = new RecipeOrderbook(
            address(weirollWalletImplementation),
            0.01e18, // 1% protocol fee
            0.001e18, // 0.1% minimum frontend fee
            owner,
            address(pointsFactory)
        );
    }

    function testCreateMarket() public {
        RecipeOrderbook.Recipe memory depositRecipe = RecipeOrderbook.Recipe(new bytes32[](0), new bytes[](0));
        RecipeOrderbook.Recipe memory withdrawRecipe = RecipeOrderbook.Recipe(new bytes32[](0), new bytes[](0));

        uint256 marketId = orderbook.createMarket(
            address(mockToken),
            1 days,
            0.002e18, // 0.2% frontend fee
            depositRecipe,
            withdrawRecipe,
            RewardStyle.Upfront
        );

        assertEq(marketId, 0);
        assertEq(orderbook.numMarkets(), 1);

        (ERC20 inputToken, uint256 lockupTime, uint256 frontendFee, , ,) = orderbook.marketIDToWeirollMarket(0);
        assertEq(address(inputToken), address(mockToken));
        assertEq(lockupTime, 1 days);
        assertEq(frontendFee, 0.002e18);
    }

    function testCreateLPOrder() public {
        // First create a market
        testCreateMarket();

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 100e18;

        vm.startPrank(user1);
        mockToken.mint(user1, 1000e18);
        mockToken.approve(address(orderbook), 1000e18);

        uint256 orderId = orderbook.createLPOrder(
            0, // marketId
            address(0), // No funding vault
            1000e18, // quantity
            block.timestamp + 1 days, // expiry
            tokensRequested,
            tokenAmountsRequested
        );

        assertEq(orderId, 0);
        assertEq(orderbook.numLPOrders(), 1);

        bytes32 orderHash = orderbook.getOrderHash(RecipeOrderbook.LPOrder(
            0, // orderId
            0, // marketId
            user1,
            address(0),
            1000e18,
            block.timestamp + 1 days,
            tokensRequested,
            tokenAmountsRequested
        ));

        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 1000e18);
        vm.stopPrank();
    }

    function testCreateIPOrder() public {
        // First create a market
        testCreateMarket();

        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockToken);
        uint256[] memory tokenAmounts = new uint256[](1);
        tokenAmounts[0] = 100e18;

        vm.startPrank(user2);
        mockToken.mint(user2, 100e18);
        mockToken.approve(address(orderbook), 100e18);

        uint256 orderId = orderbook.createIPOrder(
            0, // marketId
            1000e18, // quantity
            block.timestamp + 1 days, // expiry
            tokensOffered,
            tokenAmounts
        );

        assertEq(orderId, 0);
        assertEq(orderbook.numIPOrders(), 1);

        (uint256 targetMarketID, address ip, uint256 expiry, uint256 quantity, uint256 remainingQuantity) = orderbook.orderIDToIPOrder(0);
        assertEq(targetMarketID, 0);
        assertEq(quantity, 1000e18);
        assertEq(remainingQuantity, 1000e18);
        assertEq(expiry, block.timestamp + 1 days);
        vm.stopPrank();
    }


    function testFillIPOrder() public {
        // First create a market and an IP order
        testCreateIPOrder();

        vm.startPrank(user1);
        mockToken.mint(user1, 1000e18);
        mockToken.approve(address(mockVault), 500e18);
        mockToken.approve(address(orderbook), 500e18);
        mockVault.deposit(500e18, user1);
        mockVault.approve(address(orderbook), 1000e18);

        orderbook.fillIPOrder(0, 500e18, address(mockVault), user2);

        (, , , , uint256 remainingQuantity) = orderbook.orderIDToIPOrder(0);
        assertEq(remainingQuantity, 500e18);
        vm.stopPrank();
    }
}
