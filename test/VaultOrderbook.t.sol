// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";

import { ERC4626i } from "src/ERC4626i.sol";
import { ERC4626iFactory } from "src/ERC4626iFactory.sol";

import { VaultOrderbook } from "src/VaultOrderbook.sol";

import { Test } from "forge-std/Test.sol";

contract VaultOrderbookTest is Test {
    VaultOrderbook public orderbook = new VaultOrderbook();
    MockERC20 public baseToken;
    MockERC4626 public targetVault;
    MockERC4626 public fundingVault;
    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        baseToken = new MockERC20("Base Token", "BT");
        targetVault = new MockERC4626(baseToken);
        fundingVault = new MockERC4626(baseToken);

        baseToken.mint(alice, 1000 * 1e18);
        baseToken.mint(bob, 1000 * 1e18);

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
    }

    function testCreateLPOrder() public {
        vm.startPrank(alice);
        baseToken.approve(address(orderbook), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        uint256 orderId = orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        assertEq(orderId, 0);
        assertEq(orderbook.numOrders(), 1);
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

        // NOTE - Testcase added to address bug of expiry at timestamp, should not revert
        orderbook.createLPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp, tokensRequested, tokenRatesRequested);

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
            VaultOrderbook.LPOrder(orderId, address(targetVault), alice, address(fundingVault), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        orderbook.cancelOrder(order);

        bytes32 orderHash = orderbook.getOrderHash(order);
        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 0);

        vm.stopPrank();
    }

    function testAllocateOrder() public {
        // Setup
        vm.startPrank(alice);
        baseToken.mint(alice, 1000 * 1e18);

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
        // You'll need to implement this function in your MockERC4626 contract
        vm.mockCall(address(targetVault), abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, uint256(0), uint256(100 * 1e18)), abi.encode(2e18));

        // Allocate the order
        orderbook.allocateOrder(order, campaignIds);

        // Verify allocation
        bytes32 orderHash = orderbook.getOrderHash(order);
        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), 0);
        assertEq(baseToken.balanceOf(address(targetVault)), 100 * 1e18);
        assertEq(targetVault.balanceOf(alice), 100 * 1e18);

        vm.stopPrank();
    }
}
