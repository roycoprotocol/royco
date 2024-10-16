// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { WeirollWallet } from "src/WeirollWallet.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { Test } from "forge-std/Test.sol";
import { VM } from "lib/weiroll/contracts/VM.sol";
import { ECDSA } from "lib/solady/src/utils/ECDSA.sol";

contract WeirollWalletTest is Test {
    using ClonesWithImmutableArgs for address;

    address public WEIROLL_WALLET_IMPLEMENTATION;
    WeirollWallet public wallet;
    MockRecipeMarketHub public mockRecipeMarketHub;
    address public owner;
    uint256 public constant AMOUNT = 1 ether;
    uint256 public lockedUntil;
    bytes32 public marketHash;

    receive() external payable { }

    function setUp() public {
        WEIROLL_WALLET_IMPLEMENTATION = address(new WeirollWallet());
        mockRecipeMarketHub = new MockRecipeMarketHub();
        owner = address(this);
        lockedUntil = block.timestamp + 1 days;
        marketHash = bytes32(hex"14beef");
        wallet = createWallet(owner, address(mockRecipeMarketHub), AMOUNT, lockedUntil, true, marketHash);
    }

    function createWallet(
        address _owner,
        address _recipeMarketHub,
        uint256 _amount,
        uint256 _lockedUntil,
        bool _isForfeitable,
        bytes32 _marketHash
    )
        public
        returns (WeirollWallet)
    {
        return WeirollWallet(
            payable(WEIROLL_WALLET_IMPLEMENTATION.clone(abi.encodePacked(_owner, _recipeMarketHub, _amount, _lockedUntil, _isForfeitable, _marketHash)))
        );
    }

    function testWalletInitialization() public view {
        assertEq(wallet.owner(), owner);
        assertEq(wallet.recipeMarketHub(), address(mockRecipeMarketHub));
        assertEq(wallet.amount(), AMOUNT);
        assertEq(wallet.lockedUntil(), lockedUntil);
        assertTrue(wallet.isForfeitable());
        assertEq(wallet.marketHash(), marketHash);
        assertFalse(wallet.executed());
        assertFalse(wallet.forfeited());
    }

    function testOnlyOwnerModifier() public {
        vm.prank(address(0xdead));
        vm.expectRevert(WeirollWallet.NotOwner.selector);
        wallet.manualExecuteWeiroll(new bytes32[](0), new bytes[](0));
    }

    function testOnlyRecipeMarketHubModifier() public {
        vm.prank(address(0xdead));
        vm.expectRevert(WeirollWallet.NotRecipeMarketHub.selector);
        wallet.executeWeiroll(new bytes32[](0), new bytes[](0));
    }

    function testNotLockedModifier() public {
        uint256 shortLockTime = block.timestamp + 1 hours;
        WeirollWallet lockedWallet = createWallet(owner, address(mockRecipeMarketHub), AMOUNT, shortLockTime, true, marketHash);

        vm.expectRevert(WeirollWallet.WalletLocked.selector);
        lockedWallet.manualExecuteWeiroll(new bytes32[](0), new bytes[](0));

        // Test that it works after the lock period
        vm.warp(shortLockTime + 1);

        // Execute Weiroll to set executed to true
        vm.prank(address(mockRecipeMarketHub));
        lockedWallet.executeWeiroll(new bytes32[](0), new bytes[](0));

        // This should now succeed as the wallet is unlocked and executed
        lockedWallet.manualExecuteWeiroll(new bytes32[](0), new bytes[](0));
    }

    function testManualExecuteWeiroll() public {
        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](1);

        vm.expectRevert(WeirollWallet.WalletLocked.selector);
        wallet.manualExecuteWeiroll(commands, state);

        // Warp time to unlock the wallet
        vm.warp(lockedUntil + 1);

        // This should still fail because the wallet is not executed
        vm.expectRevert(abi.encodeWithSelector(WeirollWallet.OfferUnfilled.selector));
        wallet.manualExecuteWeiroll(commands, state);
    }

    function testExecute() public {
        address target = address(0x1234);
        uint256 value = 0.1 ether;
        bytes memory data = abi.encodeWithSignature("someFunction()");

        vm.expectRevert(WeirollWallet.WalletLocked.selector);
        wallet.execute(target, value, data);

        // Warp time to unlock the wallet
        vm.warp(lockedUntil + 1);

        // Execute Weiroll to set executed to true
        vm.prank(address(mockRecipeMarketHub));
        wallet.executeWeiroll(new bytes32[](0), new bytes[](0));

        // Check if the wallet is now executed
        assertTrue(wallet.executed());

        // Mock the target contract
        vm.etch(target, bytes("mock contract code"));
        vm.mockCall(target, value, data, abi.encode(true));

        // This should now succeed
        wallet.execute(target, value, data);

        // Test with a reverting call
        vm.mockCallRevert(target, value, data, "Mock revert");
        vm.expectRevert(abi.encodeWithSelector(WeirollWallet.RawExecutionFailed.selector));
        wallet.execute(target, value, data);
    }

    function testForfeit() public {
        assertFalse(wallet.forfeited());
        mockRecipeMarketHub.forfeitWallet(wallet);
        assertTrue(wallet.forfeited());

        // Test non-forfeitable wallet
        WeirollWallet nonForfeitableWallet = createWallet(owner, address(mockRecipeMarketHub), AMOUNT, lockedUntil, false, marketHash);
        vm.expectRevert(WeirollWallet.WalletNotForfeitable.selector);
        MockRecipeMarketHub(mockRecipeMarketHub).forfeitWallet(nonForfeitableWallet);
    }

    function testReceiveEther() public {
        uint256 initialBalance = address(wallet).balance;

        // Make sure the wallet can receive Ether
        vm.deal(address(this), 1 ether);
        (bool success,) = payable(address(wallet)).call{ value: 1 ether }("");
        assertTrue(success);

        // Check if the balance increased
        assertEq(address(wallet).balance, initialBalance + 1 ether);
    }

    function testIsValidSignatureFuzz(uint256 ownerPrivateKey, bytes32 digest, bytes memory signature) public {
        // Avoid using zero private key and have it be in the correct range for secp256k1 SKs
        vm.assume(
            ownerPrivateKey != 0 && ownerPrivateKey < 115_792_089_237_316_195_423_570_985_008_687_907_852_837_564_279_074_904_382_605_163_141_518_161_494_337
        );
        // Initialize owner address from the private key
        owner = vm.addr(ownerPrivateKey);

        // Create a new wallet with the fuzzed owner
        wallet = createWallet(owner, address(mockRecipeMarketHub), AMOUNT, lockedUntil, true, marketHash);

        // Modify digest for replay protection
        bytes32 walletSpecificDigest = keccak256(abi.encode(digest, block.chainid, address(wallet)));

        // Create a valid signature from the owner
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, walletSpecificDigest);
        bytes memory validSignature = abi.encodePacked(r, s, v);

        // Test valid signature
        bytes4 validResult = wallet.isValidSignature(digest, validSignature);
        bytes4 expectedMagicValue = 0x1626ba7e; // ERC1271_MAGIC_VALUE
        assertEq(validResult, expectedMagicValue);

        // Skip invalid signature lengths
        if (signature.length != 64 && signature.length != 65) {
            return;
        }

        // Test invalid signature
        bytes4 invalidResult = wallet.isValidSignature(digest, signature);
        assertEq(invalidResult, 0x00000000); // INVALID_SIGNATURE

        // Ensure the owner address is correctly recovered
        address recoveredSigner = ECDSA.recover(walletSpecificDigest, validSignature);
        assertEq(recoveredSigner, owner);
    }
}

contract MockRecipeMarketHub {
    function callWallet(WeirollWallet wallet, bytes32[] calldata commands, bytes[] calldata state) external payable returns (bytes[] memory) {
        return wallet.executeWeiroll(commands, state);
    }

    function forfeitWallet(WeirollWallet wallet) external {
        wallet.forfeit();
    }
}
