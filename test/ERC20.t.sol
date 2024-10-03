// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";

import { WrappedVault } from "src/WrappedVault.sol";
import { WrappedVaultFactory } from "src/WrappedVaultFactory.sol";

import { Test } from "forge-std/Test.sol";

contract ERC20Test is Test {
    ERC20 underlyingToken = ERC20(address(new MockERC20("Mock Token", "MOCK")));
    ERC4626 testVault = ERC4626(address(new MockERC4626(underlyingToken)));
    WrappedVault token;

    WrappedVaultFactory testFactory;

    address public constant REGULAR_USER = address(0xbeef);
    address public constant REFERRAL_USER = address(0x33f123);

    function setUp() public {
        vm.startPrank(address(0x1));
        testFactory = new WrappedVaultFactory(address(0x0), 0.01e18, 0.01e18, address(0x0));
        vm.stopPrank();
        token = testFactory.wrapVault(testVault, address(0x01), "Test iVault", 0.05e18);
    }

    function mintTokensTo(address to, uint256 amount) public {
        MockERC20(address(underlyingToken)).mint(address(this), amount);
        underlyingToken.approve(address(token), amount);
        token.deposit(amount, to);
    }

    function testApprove() public {
        assertTrue(token.approve(address(0xBEEF), 1e18));

        assertEq(token.allowance(address(this), address(0xBEEF)), 1e18);
    }

    function testTransfer() public {
        mintTokensTo(address(this), 1e18);

        assertTrue(token.transfer(address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18 + 10_000);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        mintTokensTo(from, 1e18);

        vm.prank(from);
        token.approve(address(this), 1e18);

        assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18 + 10_000);

        assertEq(token.allowance(from, address(this)), 0);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testInfiniteApproveTransferFrom() public {
        address from = address(0xABCD);

        mintTokensTo(from, 1e18);

        vm.prank(from);
        token.approve(address(this), type(uint256).max);

        assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18 + 10_000);

        assertEq(token.allowance(from, address(this)), type(uint256).max);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testFailTransferInsufficientBalance(address to, uint256 mintAmount, uint256 sendAmount) public {
        sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

        mintTokensTo(address(this), mintAmount);
        token.transfer(to, sendAmount);
    }

    function testFailTransferFromInsufficientAllowance(address to, uint256 approval, uint256 amount) public {
        amount = bound(amount, approval + 1, type(uint256).max);

        address from = address(0xABCD);

        mintTokensTo(from, amount);

        vm.prank(from);
        token.approve(address(this), approval);

        token.transferFrom(from, to, amount);
    }
}
