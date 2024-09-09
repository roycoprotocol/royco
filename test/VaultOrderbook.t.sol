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

    function testCreateLPOrder() public {
        vm.startPrank(alice);
        baseToken.approve(address(orderbook), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        uint256 orderId =
            orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultOrderbook.LPOrder memory order =
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        assertEq(orderId, 0);
        assertEq(orderbook.numOrders(), 1);
        assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order)), 100 * 1e18);
        vm.stopPrank();
    }

    function testCannotCreateExpiredOrder() public {
        vm.startPrank(alice);
        baseToken.approve(address(orderbook), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        vm.warp(100 days);

        vm.expectRevert(VaultOrderbook.CannotPlaceExpiredOrder.selector);
        orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp - 1, tokensRequested, tokenRatesRequested);

        assertEq(orderbook.numOrders(), 0);

        // NOTE - Testcase added to address bug of expiry at timestamp, should not revert
        uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp, tokensRequested, tokenRatesRequested);
        VaultOrderbook.LPOrder memory order =
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), block.timestamp, tokensRequested, tokenRatesRequested);

        assertEq(orderId, 0);
        assertEq(orderbook.numOrders(), 1);
        assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order)), 100 * 1e18);

        vm.stopPrank();
    }

    function testCannotCreateZeroQuantityOrder() public {
        vm.startPrank(alice);
        baseToken.approve(address(orderbook), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        vm.expectRevert(VaultOrderbook.CannotPlaceZeroQuantityOrder.selector);
        orderbook.createLPOrder(address(targetVault), address(0), 0, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        assertEq(orderbook.numOrders(), 0);

        vm.stopPrank();
    }

    function testMismatchedBaseAsset() public {
        vm.startPrank(alice);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        vm.expectRevert(VaultOrderbook.MismatchedBaseAsset.selector);
        orderbook.createLPOrder(address(targetVault), address(fundingVault2), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        assertEq(orderbook.numOrders(), 0);

        vm.stopPrank();
    }

    function testNotEnoughBaseAssetToOrder() public {
        vm.startPrank(alice);

        baseToken.approve(address(orderbook), 100 * 1e18);
        baseToken.approve(address(fundingVault), 100 * 1e18);
        fundingVault.deposit(100 * 1e18, alice);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        //Test when funding vault is the user's address, revert occurs
        vm.expectRevert(VaultOrderbook.NotEnoughBaseAssetToOrder.selector);
        orderbook.createLPOrder(address(targetVault), address(0), 2000 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        assertEq(orderbook.numOrders(), 0);

        //Test that when funding vault is an ERC4626 vault, revert occurs
        vm.expectRevert(VaultOrderbook.NotEnoughBaseAssetToOrder.selector);
        orderbook.createLPOrder(address(targetVault), address(fundingVault), 2000 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        assertEq(orderbook.numOrders(), 0);

        vm.stopPrank();
    }

    function testArrayLengthMismatch() public {
        vm.startPrank(alice);
        baseToken.mint(alice, 1000 * 1e18);
        baseToken.approve(address(orderbook), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](2);
        tokenRatesRequested[0] = 1e18;
        tokenRatesRequested[1] = 2e18;

        vm.expectRevert(VaultOrderbook.ArrayLengthMismatch.selector);
        orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        assertEq(orderbook.numOrders(), 0);

        vm.stopPrank();
    }

    function testTooManyCampaignIds() public {
        vm.startPrank(alice);

        baseToken.approve(address(orderbook), 1000 * 1e18);
        baseToken.approve(address(targetVault), 1000 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        // Create an order
        uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order =
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        vm.stopPrank();

        // Setup for allocation
        vm.startPrank(bob);
        uint256[] memory campaignIds = new uint256[](6);
        campaignIds[0] = 0;
        campaignIds[1] = 1;
        campaignIds[2] = 2;
        campaignIds[3] = 3;
        campaignIds[4] = 4;
        campaignIds[5] = 5;

        // Allocate the order
        vm.expectRevert(VaultOrderbook.TooManyCampaignIds.selector);
        orderbook.allocateOrder(order, campaignIds);

        // Verify allocation did not occur
        bytes32 orderHash = orderbook.getOrderHash(order);
        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 100 * 1e18);
        assertEq(baseToken.balanceOf(address(alice)), 1000 * 1e18);
        assertEq(targetVault.balanceOf(alice), 0);

        vm.stopPrank();
    }

    function testCannotAllocateExpiredOrder() public {
        vm.startPrank(alice);
        baseToken.approve(address(orderbook), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, 5, tokensRequested, tokenRatesRequested);
        VaultOrderbook.LPOrder memory order =
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), 5, tokensRequested, tokenRatesRequested);

        uint256[] memory campaignIds = new uint256[](0);

        vm.warp(100 days);

        vm.expectRevert(VaultOrderbook.OrderExpired.selector);
        orderbook.allocateOrder(order, campaignIds);

        // Verify allocation did not occur
        bytes32 orderHash = orderbook.getOrderHash(order);
        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 100 * 1e18);
        assertEq(baseToken.balanceOf(address(alice)), 1000 * 1e18);
        assertEq(targetVault.balanceOf(alice), 0);

        //todo - Going to add testcase to allocate an order expiring at the current timestamp to testAllocateOrder (the allocation should not revert)

        vm.stopPrank();
    }

    function testNotEnoughBaseAssetToAllocate() public {
        vm.startPrank(alice);

        baseToken.approve(address(orderbook), 1000 * 1e18);
        baseToken.approve(address(fundingVault), 1000 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        uint256 order1Id = orderbook.createLPOrder(address(targetVault), address(0), 1000 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        fundingVault.deposit(1000 * 1e18, alice);
        uint256 order2Id = orderbook.createLPOrder(address(targetVault), address(fundingVault), 1000 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order1 =
            VaultOrderbook.LPOrder(order1Id, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultOrderbook.LPOrder memory order2 = 
            VaultOrderbook.LPOrder(order2Id, address(targetVault), alice, address(fundingVault), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        uint256[] memory campaignIds = new uint256[](0);

        vm.expectRevert(VaultOrderbook.NotEnoughBaseAssetToAllocate.selector);
        orderbook.allocateOrder(order1, campaignIds);

        fundingVault.withdraw(1000 * 1e18, alice, alice);
        vm.expectRevert(VaultOrderbook.NotEnoughBaseAssetToAllocate.selector);
        orderbook.allocateOrder(order2, campaignIds);

        assertEq(baseToken.balanceOf(address(alice)), 1000 * 1e18);
        assertEq(fundingVault.balanceOf(alice), 0);
        assertEq(targetVault.balanceOf(alice), 0);
        assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order1)), 1000 * 1e18);
        assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order2)), 1000 * 1e18);

        vm.stopPrank();
    }

    function testNotEnoughCampaignIds() public {
        vm.startPrank(alice);
        baseToken.approve(address(orderbook), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        VaultOrderbook.LPOrder[] memory orders = new VaultOrderbook.LPOrder[](2);
        uint256[][] memory campaignIds = new uint256[][](0);


        uint256 order1Id = orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        uint256 order2Id =
            orderbook.createLPOrder(address(targetVault2), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order1 =
            VaultOrderbook.LPOrder(order1Id, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultOrderbook.LPOrder memory order2 =
            VaultOrderbook.LPOrder(order2Id, address(targetVault2), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        orders[0] = order1;
        orders[1] = order2;

        vm.expectRevert(VaultOrderbook.NotEnoughCampaignIds.selector);
        orderbook.allocateOrders(orders, campaignIds);

        assertEq(baseToken.balanceOf(address(alice)), 1000 * 1e18);
        assertEq(targetVault.balanceOf(alice), 0);
        assertEq(targetVault2.balanceOf(alice), 0);
        assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order1)), 100 * 1e18);
        assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order2)), 100 * 1e18);

        vm.stopPrank();
    }

    function testNotEnoughRemainingQuantity() public {
        vm.startPrank(alice);
        baseToken.approve(address(orderbook), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        uint256 orderId = 
            orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order =
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        // New - Testcase added to attempt to allocate a cancelled order
        uint256[] memory campaignIds = new uint256[](0);
        vm.expectRevert(VaultOrderbook.NotEnoughRemainingQuantity.selector);
        orderbook.allocateOrder(order, campaignIds, 200 * 1e18);

        assertEq(baseToken.balanceOf(address(alice)), 1000 * 1e18);
        assertEq(targetVault.balanceOf(alice), 0);
        assertEq(orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order)), 100 * 1e18);

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

        uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order =
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(VaultOrderbook.NotOrderCreator.selector);
        orderbook.cancelOrder(order);

        bytes32 orderHash = orderbook.getOrderHash(order);
        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 100 * 1e18);
        vm.stopPrank();
    }

    function testCancelOrder() public {
        vm.startPrank(alice);
        baseToken.mint(alice, 1000 * 1e18);
        baseToken.approve(address(orderbook), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order =
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        orderbook.cancelOrder(order);

        bytes32 orderHash = orderbook.getOrderHash(order);
        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 0);

        // New - Testcase added to attempt to allocate a cancelled order
        uint256[] memory campaignIds = new uint256[](0);
        vm.expectRevert(VaultOrderbook.OrderDoesNotExist.selector);
        orderbook.allocateOrder(order, campaignIds);

        // Verify allocation did not occur
        assertEq(baseToken.balanceOf(address(alice)), 2000 * 1e18);
        assertEq(targetVault.balanceOf(alice), 0);

        // New - Testcase added to attempt to allocate a cancelled order within a group of multiple valid orders
        uint256[][] memory moreCampaignIds = new uint256[][](3);
        moreCampaignIds[0] = new uint256[](1);
        moreCampaignIds[0][0] = 0;
        moreCampaignIds[1] = new uint256[](1);
        moreCampaignIds[1][0] = 1;
        moreCampaignIds[2] = new uint256[](1);
        moreCampaignIds[2][0] = 2;
        VaultOrderbook.LPOrder[] memory orders = new VaultOrderbook.LPOrder[](3);

        uint256 order2Id =
            orderbook.createLPOrder(address(targetVault2), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        uint256 order3Id =
            orderbook.createLPOrder(address(targetVault3), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order2 =
            VaultOrderbook.LPOrder(order2Id, address(targetVault2), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultOrderbook.LPOrder memory order3 =
            VaultOrderbook.LPOrder(order3Id, address(targetVault3), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        bytes32 order2Hash = orderbook.getOrderHash(order2);
        bytes32 order3Hash = orderbook.getOrderHash(order3);

        orders[0] = order2;
        orders[1] = order;
        orders[2] = order3;

        // Mock the previewRateAfterDeposit function
        vm.mockCall(
            address(targetVault2), 
            abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, uint256(0), uint256(100 * 1e18)), 
            abi.encode(2e18)
            );
        vm.mockCall(
            address(targetVault3), 
            abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, uint256(0), uint256(100 * 1e18)), 
            abi.encode(2e18)
            );
        // Mock the campaignToToken variable
        vm.mockCall(
            address(targetVault2),
            abi.encodeWithSelector(bytes4(keccak256("campaignToToken(uint256)")), uint256(0)),
            abi.encode(address(baseToken)) // Mocking the address return
        );
        vm.mockCall(
            address(targetVault3),
            abi.encodeWithSelector(bytes4(keccak256("campaignToToken(uint256)")), uint256(0)),
            abi.encode(address(baseToken)) // Mocking the address return
        );

        vm.expectRevert(VaultOrderbook.OrderDoesNotExist.selector);
        orderbook.allocateOrders(orders, moreCampaignIds);



        //Verify none of the orders allocated
        assertEq(targetVault.balanceOf(alice), 0);
        assertEq(targetVault2.balanceOf(alice), 0);
        assertEq(targetVault3.balanceOf(alice), 0);

        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 0);
        assertEq(orderbook.orderHashToRemainingQuantity(order2Hash), 100 * 1e18);
        assertEq(orderbook.orderHashToRemainingQuantity(order3Hash), 100 * 1e18);

        assertEq(baseToken.balanceOf(address(alice)), 2000 * 1e18);

        vm.stopPrank();
    }

    function testOrderConditionsNotMet() public {
        vm.startPrank(alice);

        baseToken.approve(address(orderbook), 1000 * 1e18);
        baseToken.approve(address(targetVault), 1000 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 5e18;

        // Create an order
        uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order =
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        vm.stopPrank();

        // Setup for allocation
        vm.startPrank(bob);
        uint256[] memory campaignIds = new uint256[](1);
        campaignIds[0] = 0; // Assuming campaign ID 0 exists

        // Mock the previewRateAfterDeposit function
        vm.mockCall(
            address(targetVault), 
            abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, uint256(0), uint256(100 * 1e18)), 
            abi.encode(2e18)
            );
        // Mock the campaignToToken variable
        vm.mockCall(
            address(targetVault),
            abi.encodeWithSelector(bytes4(keccak256("campaignToToken(uint256)")), uint256(0)),
            abi.encode(address(baseToken)) // Mocking the address return
        );
        // Allocate the order
        vm.expectRevert(VaultOrderbook.OrderConditionsNotMet.selector);
        orderbook.allocateOrder(order, campaignIds);

        // Verify allocation did not occur
        bytes32 orderHash = orderbook.getOrderHash(order);
        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 100 * 1e18);
        assertEq(baseToken.balanceOf(address(alice)), 1000 * 1e18);
        assertEq(targetVault.balanceOf(alice), 0);

        vm.stopPrank();
    }

    function testAllocateOrder() public {
        vm.startPrank(alice);

        baseToken.approve(address(orderbook), 1000 * 1e18);
        baseToken.approve(address(targetVault), 1000 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        // Create an order
        uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order =
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        vm.stopPrank();

        // Setup for allocation
        vm.startPrank(bob);
        uint256[] memory campaignIds = new uint256[](1);
        campaignIds[0] = 0; // Assuming campaign ID 0 exists

        // Mock the previewRateAfterDeposit function
        vm.mockCall(
            address(targetVault), 
            abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, uint256(0), uint256(100 * 1e18)), 
            abi.encode(2e18)
            );
        // Mock the campaignToToken variable
        vm.mockCall(
            address(targetVault),
            abi.encodeWithSelector(bytes4(keccak256("campaignToToken(uint256)")), uint256(0)),
            abi.encode(address(baseToken)) // Mocking the address return
        );
        // Allocate the order
        orderbook.allocateOrder(order, campaignIds);

        // Verify allocation
        bytes32 orderHash = orderbook.getOrderHash(order);
        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 0);
        assertEq(baseToken.balanceOf(address(targetVault)), 100 * 1e18);
        assertEq(targetVault.balanceOf(alice), 100 * 1e18);

        vm.stopPrank();
    }

    function testAllocateOrders() public {
        vm.startPrank(alice);
        baseToken.approve(address(orderbook), 300 * 1e18);
        baseToken.approve(address(fundingVault), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        uint256 order1Id = 
            orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        uint256 order2Id = 
            orderbook.createLPOrder(address(targetVault2), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        uint256 order3Id = 
            orderbook.createLPOrder(address(targetVault3), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.LPOrder memory order1 =
            VaultOrderbook.LPOrder(order1Id, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultOrderbook.LPOrder memory order2 =
            VaultOrderbook.LPOrder(order2Id, address(targetVault2), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultOrderbook.LPOrder memory order3 =
            VaultOrderbook.LPOrder(order3Id, address(targetVault3), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        
        uint256[][] memory moreCampaignIds = new uint256[][](3);
        moreCampaignIds[0] = new uint256[](1);
        moreCampaignIds[0][0] = 0;
        moreCampaignIds[1] = new uint256[](1);
        moreCampaignIds[1][0] = 1;
        moreCampaignIds[2] = new uint256[](1);
        moreCampaignIds[2][0] = 2;
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
            abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, uint256(0), uint256(100 * 1e18)), 
            abi.encode(2e18)
            );
        vm.mockCall(
            address(targetVault2), 
            abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, uint256(1), uint256(100 * 1e18)), 
            abi.encode(2e18)
            );
        vm.mockCall(
            address(targetVault3), 
            abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, uint256(2), uint256(100 * 1e18)), 
            abi.encode(2e18)
            );
        // Mock the campaignToToken variable
        vm.mockCall(
            address(targetVault),
            abi.encodeWithSelector(bytes4(keccak256("campaignToToken(uint256)")), uint256(0)),
            abi.encode(address(baseToken)) // Mocking the address return
        );
        vm.mockCall(
            address(targetVault2),
            abi.encodeWithSelector(bytes4(keccak256("campaignToToken(uint256)")), uint256(1)),
            abi.encode(address(baseToken)) // Mocking the address return
        );
        vm.mockCall(
            address(targetVault3),
            abi.encodeWithSelector(bytes4(keccak256("campaignToToken(uint256)")), uint256(2)),
            abi.encode(address(baseToken)) // Mocking the address return
        );

        orderbook.allocateOrders(orders, moreCampaignIds);

        //Verify none of the orders allocated
        assertEq(targetVault.balanceOf(alice), 100*1e18);
        assertEq(targetVault2.balanceOf(alice), 100*1e18);
        assertEq(targetVault3.balanceOf(alice), 100*1e18);

        assertEq(orderbook.orderHashToRemainingQuantity(order1Hash), 0);
        assertEq(orderbook.orderHashToRemainingQuantity(order2Hash), 0);
        assertEq(orderbook.orderHashToRemainingQuantity(order3Hash), 0);

        assertEq(baseToken.balanceOf(address(alice)), 1000 * 1e18 - 300 * 1e18);

        vm.stopPrank();
    }
}
