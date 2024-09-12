// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";

import { ERC4626i } from "src/ERC4626i.sol";
import { ERC4626iFactory } from "src/ERC4626iFactory.sol";

import { VaultOrderbook } from "src/VaultOrderbook.sol";

// import { Test } from "../lib/forge-std/src/Test.sol";
import { Test, console } from "forge-std/Test.sol";

contract VaultOrderbookTest is Test {
   VaultOrderbook public orderbook = new VaultOrderbook();
   MockERC20 public baseToken;
   MockERC20 public baseToken2;
   MockERC4626 public targetVault;
   MockERC4626 public targetVault2;
   MockERC4626 public targetVault3;
   MockERC4626 public fundingVault;
   MockERC4626 public fundingVault2;
   address public alice = address(0x1);
   address public bob = address(0x2);

   function setUp() public {
       baseToken = new MockERC20("Base Token", "BT");
       baseToken2 = new MockERC20("Base Token2", "BT2");

       targetVault = new MockERC4626(baseToken);
       targetVault2 = new MockERC4626(baseToken);
       targetVault3 = new MockERC4626(baseToken);
       fundingVault = new MockERC4626(baseToken);
       fundingVault2 = new MockERC4626(baseToken2);

       baseToken.mint(alice, 1000 * 1e18);
       baseToken.mint(bob, 1000 * 1e18);

       vm.label(alice, "Alice");
       vm.label(bob, "Bob");
   }

   function testConstructor() public {
       assertEq(orderbook.numOrders(), 0);
   }

   function testCreateLPOrder(uint256 quantity, uint256 rate, uint256 timeToExpiry, uint256 tokenRateRequested) public {
        vm.assume(quantity > 0);
        vm.assume(quantity <= type(uint256).max / quantity);
        vm.assume(timeToExpiry >= block.timestamp);

        //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);
       baseToken.approve(address(orderbook), 2*quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;
       
       uint256 order1Id =
           orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultOrderbook.LPOrder memory order1 =
           VaultOrderbook.LPOrder(order1Id, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(order1Id, 0);
       assertEq(orderbook.numOrders(), 1);
       assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order1)), quantity);

       baseToken.approve(address(fundingVault), quantity);
       fundingVault.deposit(quantity, alice);

       uint256 order2Id =
           orderbook.createLPOrder(address(targetVault), address(fundingVault), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultOrderbook.LPOrder memory order2 =
           VaultOrderbook.LPOrder(order2Id, address(targetVault), alice, address(fundingVault), timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(order2Id, 1);
       assertEq(orderbook.numOrders(), 2);
       assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order2)), quantity);

       vm.stopPrank();
   }

   function testCannotCreateExpiredOrder(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
        vm.assume(block.timestamp + 1 days <= type(uint256).max - timeToExpiry);
        vm.assume(quantity > 0);
        vm.assume(quantity <= type(uint256).max / quantity);
        vm.assume(timeToExpiry > 1 days);

        //todo - delete once setup is fixed
        vm.prank(alice);
        baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);
       baseToken.approve(address(orderbook), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       vm.warp(timeToExpiry + 1 days);

       vm.expectRevert(VaultOrderbook.CannotPlaceExpiredOrder.selector);
       orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(orderbook.numOrders(), 0);

       // NOTE - Testcase added to address bug of expiry at timestamp, should not revert
       uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), quantity, block.timestamp, tokensRequested, tokenRatesRequested);
       VaultOrderbook.LPOrder memory order =
           VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), block.timestamp, tokensRequested, tokenRatesRequested);

       assertEq(orderId, 0);
       assertEq(orderbook.numOrders(), 1);
       assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order)), quantity);

       vm.stopPrank();
   }

   function testCannotCreateZeroQuantityOrder(uint256 timeToExpiry, uint256 tokenRateRequested) public {
        //todo - delete once setup is fixed
        vm.prank(alice);
        baseToken.burn(alice, 1000 * 1e18);

       vm.startPrank(alice);
       baseToken.approve(address(orderbook), 100 * 1e18);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       vm.expectRevert(VaultOrderbook.CannotPlaceZeroQuantityOrder.selector);
       orderbook.createLPOrder(address(targetVault), address(0), 0, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(orderbook.numOrders(), 0);

       vm.stopPrank();
   }

   function testMismatchedBaseAsset(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
        vm.assume(quantity > 0);
        vm.assume(quantity <= type(uint256).max / quantity);
        vm.assume(timeToExpiry >= block.timestamp);

        //todo - delete once setup is fixed
        vm.prank(alice);
        baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);
       vm.assume(timeToExpiry > block.timestamp);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       vm.expectRevert(VaultOrderbook.MismatchedBaseAsset.selector);
       orderbook.createLPOrder(address(targetVault), address(fundingVault2), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(orderbook.numOrders(), 0);

       vm.stopPrank();
   }

   function testNotEnoughBaseAssetToOrder(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 1);
       vm.assume(quantity <= type(uint256).max / quantity);
       vm.assume(timeToExpiry >= block.timestamp);

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(orderbook), quantity);
       baseToken.approve(address(fundingVault), quantity);
       fundingVault.deposit(quantity-1, alice);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       //Test when funding vault is the user's address, revert occurs
       vm.expectRevert(VaultOrderbook.NotEnoughBaseAssetToOrder.selector);
       orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(orderbook.numOrders(), 0);

       //Test that when funding vault is an ERC4626 vault, revert occurs
       vm.expectRevert(VaultOrderbook.NotEnoughBaseAssetToOrder.selector);
       orderbook.createLPOrder(address(targetVault), address(fundingVault), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(orderbook.numOrders(), 0);

       vm.stopPrank();
   }

   function testArrayLengthMismatch(uint256 quantity, uint256 timeToExpiry, uint256 token1RateRequested, uint256 token2RateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity);
       vm.assume(timeToExpiry >= block.timestamp);

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       vm.startPrank(alice);
       baseToken.mint(alice, quantity);
       baseToken.approve(address(orderbook), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](2);
       tokenRatesRequested[0] = token1RateRequested;
       tokenRatesRequested[1] = token2RateRequested;

       vm.expectRevert(VaultOrderbook.ArrayLengthMismatch.selector);
       orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(orderbook.numOrders(), 0);

       vm.stopPrank();
   }

   function testCannotAllocateExpiredOrder(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp + 1 days <= type(uint256).max - timeToExpiry);

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);
       baseToken.approve(address(orderbook), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultOrderbook.LPOrder memory order =
           VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.warp(timeToExpiry + 1 days);

       vm.expectRevert(VaultOrderbook.OrderExpired.selector);
       orderbook.allocateOrder(order);

       // Verify allocation did not occur
       bytes32 orderHash = orderbook.getOrderHash(order);
       assertEq(orderbook.orderHashToRemainingQuantity(orderHash), quantity);
       assertEq(baseToken.balanceOf(address(alice)), quantity);
       assertEq(targetVault.balanceOf(alice), 0);

       //todo - Going to add testcase to allocate an order expiring at the current timestamp to testAllocateOrder (the allocation should not revert)

       vm.stopPrank();
   }

   function testNotEnoughBaseAssetToAllocate(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(orderbook), quantity);
       baseToken.approve(address(fundingVault), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       uint256 order1Id = orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       fundingVault.deposit(quantity, alice);
       uint256 order2Id = orderbook.createLPOrder(address(targetVault), address(fundingVault), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultOrderbook.LPOrder memory order1 =
           VaultOrderbook.LPOrder(order1Id, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultOrderbook.LPOrder memory order2 =
           VaultOrderbook.LPOrder(order2Id, address(targetVault), alice, address(fundingVault), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.expectRevert(VaultOrderbook.NotEnoughBaseAssetToAllocate.selector);
       orderbook.allocateOrder(order1);

       fundingVault.withdraw(quantity, alice, alice);
       vm.expectRevert(VaultOrderbook.NotEnoughBaseAssetToAllocate.selector);
       orderbook.allocateOrder(order2);

       assertEq(baseToken.balanceOf(address(alice)), quantity);
       assertEq(fundingVault.balanceOf(alice), 0);
       assertEq(targetVault.balanceOf(alice), 0);
       assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order1)), quantity);
       assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order2)), quantity);

       vm.stopPrank();
   }

   function testNotEnoughRemainingQuantity(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, 2*quantity);

       vm.startPrank(alice);
       baseToken.approve(address(orderbook), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       uint256 orderId =
           orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultOrderbook.LPOrder memory order =
           VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       // New - Testcase added to attempt to allocate a cancelled order

       vm.expectRevert(VaultOrderbook.NotEnoughRemainingQuantity.selector);
       orderbook.allocateOrder(order, quantity+1);

       assertEq(baseToken.balanceOf(address(alice)), 2*quantity);
       assertEq(targetVault.balanceOf(alice), 0);
       assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order)), quantity);

       vm.stopPrank();
   }

   function testNotOrderCreator() public {
       vm.startPrank(alice);
       baseToken.mint(alice, 1000 * 1e18);
       baseToken.approve(address(orderbook), 100 * 1e18);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = 1e18;

       uint256 orderId = orderbook.createAPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

       VaultOrderbook.APOrder memory order =
           VaultOrderbook.APOrder(orderId, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

       vm.stopPrank();

       vm.startPrank(bob);
       vm.expectRevert(VaultOrderbook.NotOrderCreator.selector);
       orderbook.cancelOrder(order);

       bytes32 orderHash = orderbook.getOrderHash(order);
       assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 100 * 1e18);
       vm.stopPrank();
   }

   function testCancelOrder(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, 2*quantity);

       vm.startPrank(alice);
       baseToken.approve(address(orderbook), 2*quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultOrderbook.LPOrder memory order =
           VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       orderbook.cancelOrder(order);

       bytes32 orderHash = orderbook.getOrderHash(order);
       assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 0);

       // New - Testcase added to attempt to allocate a cancelled order

       vm.expectRevert(VaultOrderbook.OrderDoesNotExist.selector);
       orderbook.allocateOrder(order);

       // Verify allocation did not occur
       assertEq(baseToken.balanceOf(address(alice)), 2*quantity);
       assertEq(targetVault.balanceOf(alice), 0);

       // New - Testcase added to attempt to allocate a cancelled order within a group of multiple valid orders
       VaultOrderbook.LPOrder[] memory orders = new VaultOrderbook.LPOrder[](3);

       uint256 order2Id =
           orderbook.createLPOrder(address(targetVault2), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       uint256 order3Id =
           orderbook.createLPOrder(address(targetVault3), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultOrderbook.LPOrder memory order2 =
           VaultOrderbook.LPOrder(order2Id, address(targetVault2), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultOrderbook.LPOrder memory order3 =
           VaultOrderbook.LPOrder(order3Id, address(targetVault3), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       bytes32 order2Hash = orderbook.getOrderHash(order2);
       bytes32 order3Hash = orderbook.getOrderHash(order3);

       orders[0] = order2;
       orders[1] = order;
       orders[2] = order3;

       // Mock the previewRateAfterDeposit function
       vm.mockCall(
           address(targetVault2),
           abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), uint256(quantity)),
           abi.encode(tokenRateRequested)
           );

       vm.expectRevert(VaultOrderbook.OrderDoesNotExist.selector);
       orderbook.allocateOrders(orders);

       //Verify none of the orders allocated
       assertEq(targetVault.balanceOf(alice), 0);
       assertEq(targetVault2.balanceOf(alice), 0);
       assertEq(targetVault3.balanceOf(alice), 0);

       assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 0);
       assertEq(orderbook.orderHashToRemainingQuantity(order2Hash), quantity);
       assertEq(orderbook.orderHashToRemainingQuantity(order3Hash), quantity);

       assertEq(baseToken.balanceOf(address(alice)), 2*quantity);

       vm.stopPrank();
   }

   function testOrderConditionsNotMet(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);
       vm.assume(tokenRateRequested > 1);

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(orderbook), quantity);
       baseToken.approve(address(targetVault), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       // Create an order
       uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultOrderbook.LPOrder memory order =
           VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.stopPrank();

       // Setup for allocation
       vm.startPrank(bob);

       // Mock the previewRateAfterDeposit function
       vm.mockCall(
           address(targetVault),
           abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(uint256(tokenRateRequested-1))
           );
       // Allocate the order
       vm.expectRevert(VaultOrderbook.OrderConditionsNotMet.selector);
       orderbook.allocateOrder(order);

       // Verify allocation did not occur
       bytes32 orderHash = orderbook.getOrderHash(order);
       assertEq(orderbook.orderHashToRemainingQuantity(orderHash), quantity);
       assertEq(baseToken.balanceOf(address(alice)), quantity);
       assertEq(targetVault.balanceOf(alice), 0);

       vm.stopPrank();
   }

   function testAllocateOrderFrom0(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);
       vm.assume(tokenRateRequested > 1);

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(orderbook), quantity);
       baseToken.approve(address(targetVault), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       // Create an order
       uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultOrderbook.LPOrder memory order =
           VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.stopPrank();

       // Setup for allocation
       vm.startPrank(bob);

       // Mock the previewRateAfterDeposit function
       vm.mockCall(
           address(targetVault),
           abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRateRequested)
           );
       // Allocate the order
       orderbook.allocateOrder(order);

       // Verify allocation
       bytes32 orderHash = orderbook.getOrderHash(order);
       assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 0);
       assertEq(baseToken.balanceOf(address(targetVault)), quantity);
       assertEq(targetVault.balanceOf(alice), quantity);

       vm.stopPrank();
   }


   function testAllocateOrderFromVault(uint256 timeToExpiry, uint256 tokenRateRequested) public {
    //    vm.assume(quantity > 0);
    //    vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);
       vm.assume(tokenRateRequested > 1);
       uint256 quantity = 1;
       timeToExpiry = block.timestamp + 1 days;
       tokenRateRequested = 1e18;

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       baseToken.mint(alice, quantity);
       baseToken.mint(bob, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(orderbook), quantity);
       baseToken.approve(address(targetVault), quantity);
       baseToken.approve(address(fundingVault), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;
       fundingVault.deposit(quantity, alice);

       // Create an order
       uint256 orderId = orderbook.createLPOrder(address(targetVault), address(fundingVault), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultOrderbook.LPOrder memory order =
           VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(fundingVault), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.stopPrank();

       // Setup for allocation
       vm.startPrank(bob);


       baseToken.approve(address(orderbook), quantity);
       baseToken.approve(address(targetVault), quantity);
       baseToken.approve(address(fundingVault), quantity);
       fundingVault.deposit(quantity, bob);

       // Mock the previewRateAfterDeposit function
       vm.mockCall(
           address(targetVault),
           abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRateRequested)
           );
       // Allocate the order
       orderbook.allocateOrder(order);

       // Verify allocation
       bytes32 orderHash = orderbook.getOrderHash(order);
       assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 0);
       assertEq(targetVault.balanceOf(alice), quantity);
         assertEq(fundingVault.balanceOf(alice), 0);

       vm.stopPrank();
   }

   function testAllocateOrders(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
        vm.assume(quantity > 0);
        vm.assume(quantity <= type(uint256).max / quantity/3);
        vm.assume(timeToExpiry >= block.timestamp);
        vm.assume(block.timestamp <= timeToExpiry);
        vm.assume(tokenRateRequested > 1);

        baseToken.mint(alice, 3*quantity);

       //todo - delete once setup is fixed
       vm.prank(alice);
       baseToken.burn(alice, 1000 * 1e18);

       vm.startPrank(alice);
        baseToken.approve(address(orderbook), quantity*3);
        baseToken.approve(address(targetVault), quantity*3);

       address[] memory tokensRequested = new address[](3);
       tokensRequested[0] = address(baseToken);
       tokensRequested[1] = address(baseToken);
       tokensRequested[2] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](3);
        tokenRatesRequested[0] = tokenRateRequested;
        tokenRatesRequested[1] = tokenRateRequested;
        tokenRatesRequested[2] = tokenRateRequested;


       uint256 order1Id =
           orderbook.createLPOrder(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       uint256 order2Id =
           orderbook.createLPOrder(address(targetVault2), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       uint256 order3Id =
           orderbook.createLPOrder(address(targetVault3), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultOrderbook.LPOrder memory order1 =
           VaultOrderbook.LPOrder(order1Id, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultOrderbook.LPOrder memory order2 =
           VaultOrderbook.LPOrder(order2Id, address(targetVault2), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultOrderbook.LPOrder memory order3 =
           VaultOrderbook.LPOrder(order3Id, address(targetVault3), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
      
       VaultOrderbook.LPOrder[] memory orders = new VaultOrderbook.LPOrder[](3);

       bytes32 order1Hash = orderbook.getOrderHash(order1);
       bytes32 order2Hash = orderbook.getOrderHash(order2);
       bytes32 order3Hash = orderbook.getOrderHash(order3);

       orders[0] = order1;
       orders[1] = order2;
       orders[2] = order3;

       // Mock the previewRateAfterDeposit function
       vm.mockCall(
           address(targetVault),
           abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRatesRequested[0])
           );
       vm.mockCall(
           address(targetVault2),
           abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRatesRequested[1])
           );
       vm.mockCall(
           address(targetVault3),
           abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRatesRequested[2])
           );

       orderbook.allocateOrders(orders);

       //Verify all of the orders allocated
       assertEq(targetVault.balanceOf(alice), quantity);
       assertEq(targetVault2.balanceOf(alice), quantity);
       assertEq(targetVault3.balanceOf(alice), quantity);

       assertEq(orderbook.orderHashToRemainingQuantity(order1Hash), 0);
       assertEq(orderbook.orderHashToRemainingQuantity(order2Hash), 0);
       assertEq(orderbook.orderHashToRemainingQuantity(order3Hash), 0);

       assertEq(baseToken.balanceOf(address(alice)), 0);

       vm.stopPrank();
   }
}