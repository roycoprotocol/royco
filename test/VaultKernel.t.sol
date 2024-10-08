// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";

import { WrappedVault } from "src/WrappedVault.sol";
import { WrappedVaultFactory } from "src/WrappedVaultFactory.sol";

import { VaultKernel } from "src/VaultKernel.sol";

// import { Test } from "../lib/forge-std/src/Test.sol";
import { Test, console } from "forge-std/Test.sol";

contract VaultKernelTest is Test {
   VaultKernel public vaultKernel = new VaultKernel();
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

    //    baseToken.mint(alice, 1000 * 1e18);
    //    baseToken.mint(bob, 1000 * 1e18);

       vm.label(alice, "Alice");
       vm.label(bob, "Bob");
   }

   function testConstructor() view public {
       assertEq(vaultKernel.numOffers(), 0);
   }

   function testCreateAPOffer(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
        vm.assume(quantity > 0);
        vm.assume(quantity <= type(uint256).max / quantity);
        vm.assume(timeToExpiry >= block.timestamp);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);
       baseToken.approve(address(vaultKernel), 2*quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;
       
       uint256 offer1Id =
           vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultKernel.APOffer memory offer1 =
           VaultKernel.APOffer(offer1Id, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(offer1Id, 0);
       assertEq(vaultKernel.numOffers(), 1);
       assertEq(vaultKernel.offerHashToRemainingQuantity(vaultKernel.getOfferHash(offer1)), quantity);

       baseToken.approve(address(fundingVault), quantity);
       fundingVault.deposit(quantity, alice);

       uint256 offer2Id =
           vaultKernel.createAPOffer(address(targetVault), address(fundingVault), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultKernel.APOffer memory offer2 =
           VaultKernel.APOffer(offer2Id, address(targetVault), alice, address(fundingVault), timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(offer2Id, 1);
       assertEq(vaultKernel.numOffers(), 2);
       assertEq(vaultKernel.offerHashToRemainingQuantity(vaultKernel.getOfferHash(offer2)), quantity);

       vm.stopPrank();
   }

   function testCannotCreateExpiredOffer(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
        vm.assume(block.timestamp + 1 days <= type(uint256).max - timeToExpiry);
        vm.assume(quantity > 0);
        vm.assume(quantity <= type(uint256).max / quantity);
        vm.assume(timeToExpiry > 1 days);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);
       baseToken.approve(address(vaultKernel), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       vm.warp(timeToExpiry + 1 days);

       vm.expectRevert(VaultKernel.CannotPlaceExpiredOffer.selector);
       vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(vaultKernel.numOffers(), 0);

       // NOTE - Testcase added to address bug of expiry at timestamp, should not revert
       uint256 offerId = vaultKernel.createAPOffer(address(targetVault), address(0), quantity, block.timestamp, tokensRequested, tokenRatesRequested);
       VaultKernel.APOffer memory offer =
           VaultKernel.APOffer(offerId, address(targetVault), alice, address(0), block.timestamp, tokensRequested, tokenRatesRequested);

       assertEq(offerId, 0);
       assertEq(vaultKernel.numOffers(), 1);
       assertEq(vaultKernel.offerHashToRemainingQuantity(vaultKernel.getOfferHash(offer)), quantity);

       vm.stopPrank();
   }

   function testCannotCreateZeroQuantityOffer(uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.startPrank(alice);
       baseToken.approve(address(vaultKernel), 100 * 1e18);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       vm.expectRevert(VaultKernel.CannotPlaceZeroQuantityOffer.selector);
       vaultKernel.createAPOffer(address(targetVault), address(0), 0, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(vaultKernel.numOffers(), 0);

       vm.stopPrank();
   }

   function testMismatchedBaseAsset(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
        vm.assume(quantity > 0);
        vm.assume(quantity <= type(uint256).max / quantity);
        vm.assume(timeToExpiry >= block.timestamp);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);
       vm.assume(timeToExpiry > block.timestamp);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       vm.expectRevert(VaultKernel.MismatchedBaseAsset.selector);
       vaultKernel.createAPOffer(address(targetVault), address(fundingVault2), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(vaultKernel.numOffers(), 0);

       vm.stopPrank();
   }

   function testNotEnoughBaseAssetToOffer(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 1);
       vm.assume(quantity <= type(uint256).max / quantity);
       vm.assume(timeToExpiry >= block.timestamp);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(vaultKernel), quantity);
       baseToken.approve(address(fundingVault), quantity);
       fundingVault.deposit(quantity-1, alice);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       //Test when funding vault is the user's address, revert occurs
       vm.expectRevert(VaultKernel.NotEnoughBaseAssetToOffer.selector);
       vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(vaultKernel.numOffers(), 0);

       //Test that when funding vault is an ERC4626 vault, revert occurs
       vm.expectRevert(VaultKernel.NotEnoughBaseAssetToOffer.selector);
       vaultKernel.createAPOffer(address(targetVault), address(fundingVault), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(vaultKernel.numOffers(), 0);

       vm.stopPrank();
   }

   function testArrayLengthMismatch(uint256 quantity, uint256 timeToExpiry, uint256 token1RateRequested, uint256 token2RateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity);
       vm.assume(timeToExpiry >= block.timestamp);

       vm.startPrank(alice);
       baseToken.mint(alice, quantity);
       baseToken.approve(address(vaultKernel), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](2);
       tokenRatesRequested[0] = token1RateRequested;
       tokenRatesRequested[1] = token2RateRequested;

       vm.expectRevert(VaultKernel.ArrayLengthMismatch.selector);
       vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       assertEq(vaultKernel.numOffers(), 0);

       vm.stopPrank();
   }

   function testCannotAllocateExpiredOffer(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp + 1 days <= type(uint256).max - timeToExpiry);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);
       baseToken.approve(address(vaultKernel), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       uint256 offerId = vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultKernel.APOffer memory offer =
           VaultKernel.APOffer(offerId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.warp(timeToExpiry + 1 days);

       vm.expectRevert(VaultKernel.OfferExpired.selector);
       vaultKernel.allocateOffer(offer);

       // Verify allocation did not occur
       bytes32 offerHash = vaultKernel.getOfferHash(offer);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offerHash), quantity);
       assertEq(baseToken.balanceOf(address(alice)), quantity);
       assertEq(targetVault.balanceOf(alice), 0);

       //todo - Going to add testcase to allocate an offer expiring at the current timestamp to testAllocateOffer (the allocation should not revert)

       vm.stopPrank();
   }

   function testNotEnoughBaseAssetToAllocate(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(vaultKernel), quantity);
       baseToken.approve(address(fundingVault), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       uint256 offer1Id = vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       fundingVault.deposit(quantity, alice);
       uint256 offer2Id = vaultKernel.createAPOffer(address(targetVault), address(fundingVault), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultKernel.APOffer memory offer1 =
           VaultKernel.APOffer(offer1Id, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultKernel.APOffer memory offer2 =
           VaultKernel.APOffer(offer2Id, address(targetVault), alice, address(fundingVault), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.expectRevert(VaultKernel.NotEnoughBaseAssetToAllocate.selector);
       vaultKernel.allocateOffer(offer1);

       fundingVault.withdraw(quantity, alice, alice);
       vm.expectRevert(VaultKernel.NotEnoughBaseAssetToAllocate.selector);
       vaultKernel.allocateOffer(offer2);

       assertEq(baseToken.balanceOf(address(alice)), quantity);
       assertEq(fundingVault.balanceOf(alice), 0);
       assertEq(targetVault.balanceOf(alice), 0);
       assertEq(vaultKernel.offerHashToRemainingQuantity(vaultKernel.getOfferHash(offer1)), quantity);
       assertEq(vaultKernel.offerHashToRemainingQuantity(vaultKernel.getOfferHash(offer2)), quantity);

       vm.stopPrank();
   }

   function testNotEnoughRemainingQuantity(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);

       baseToken.mint(alice, 2*quantity);

       vm.startPrank(alice);
       baseToken.approve(address(vaultKernel), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       uint256 offerId =
           vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultKernel.APOffer memory offer =
           VaultKernel.APOffer(offerId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       // New - Testcase added to attempt to allocate a cancelled offer

       vm.expectRevert(VaultKernel.NotEnoughRemainingQuantity.selector);
       vaultKernel.allocateOffer(offer, quantity+1);

       assertEq(baseToken.balanceOf(address(alice)), 2*quantity);
       assertEq(targetVault.balanceOf(alice), 0);
       assertEq(vaultKernel.offerHashToRemainingQuantity(vaultKernel.getOfferHash(offer)), quantity);

       vm.stopPrank();
   }

   function testNotOfferCreator() public {
       vm.startPrank(alice);
       baseToken.mint(alice, 1000 * 1e18);
       baseToken.approve(address(vaultKernel), 100 * 1e18);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = 1e18;

       uint256 offerId = vaultKernel.createAPOffer(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

       VaultKernel.APOffer memory offer =
           VaultKernel.APOffer(offerId, address(targetVault), alice, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

       vm.stopPrank();

       vm.startPrank(bob);
       vm.expectRevert(VaultKernel.NotOfferCreator.selector);
       vaultKernel.cancelOffer(offer);

       bytes32 offerHash = vaultKernel.getOfferHash(offer);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offerHash), 100 * 1e18);
       vm.stopPrank();
   }

   function testCancelOffer(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);

       baseToken.mint(alice, 2*quantity);

       vm.startPrank(alice);
       baseToken.approve(address(vaultKernel), 2*quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       uint256 offerId = vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultKernel.APOffer memory offer =
           VaultKernel.APOffer(offerId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       vaultKernel.cancelOffer(offer);

       bytes32 offerHash = vaultKernel.getOfferHash(offer);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offerHash), 0);

       // New - Testcase added to attempt to allocate a cancelled offer

       vm.expectRevert(VaultKernel.OfferDoesNotExist.selector);
       vaultKernel.allocateOffer(offer);

       // Verify allocation did not occur
       assertEq(baseToken.balanceOf(address(alice)), 2*quantity);
       assertEq(targetVault.balanceOf(alice), 0);

       // New - Testcase added to attempt to allocate a cancelled offer within a group of multiple valid offers
       VaultKernel.APOffer[] memory offers = new VaultKernel.APOffer[](3);

       uint256 offer2Id =
           vaultKernel.createAPOffer(address(targetVault2), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       uint256 offer3Id =
           vaultKernel.createAPOffer(address(targetVault3), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultKernel.APOffer memory offer2 =
           VaultKernel.APOffer(offer2Id, address(targetVault2), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultKernel.APOffer memory offer3 =
           VaultKernel.APOffer(offer3Id, address(targetVault3), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       bytes32 offer2Hash = vaultKernel.getOfferHash(offer2);
       bytes32 offer3Hash = vaultKernel.getOfferHash(offer3);

       offers[0] = offer2;
       offers[1] = offer;
       offers[2] = offer3;

       // Mock the previewRateAfterDeposit function
        vm.mockCall(
            address(targetVault2), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
       vm.mockCall(
           address(targetVault2),
           abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), uint256(quantity)),
           abi.encode(tokenRateRequested)
           );

       vm.expectRevert(VaultKernel.OfferDoesNotExist.selector);
        uint256[] memory fillAmounts = new uint256[](3);
        fillAmounts[0] = type(uint256).max;
        fillAmounts[1] = type(uint256).max;
        fillAmounts[2] = type(uint256).max;
        vaultKernel.allocateOffers(offers, fillAmounts);

       //Verify none of the offers allocated
       assertEq(targetVault.balanceOf(alice), 0);
       assertEq(targetVault2.balanceOf(alice), 0);
       assertEq(targetVault3.balanceOf(alice), 0);

       assertEq(vaultKernel.offerHashToRemainingQuantity(offerHash), 0);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offer2Hash), quantity);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offer3Hash), quantity);

       assertEq(baseToken.balanceOf(address(alice)), 2*quantity);

       vm.stopPrank();
   }

   function testOfferConditionsNotMet(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);
       vm.assume(tokenRateRequested > 1);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(vaultKernel), quantity);
       baseToken.approve(address(targetVault), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       // Create an offer
       uint256 offerId = vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultKernel.APOffer memory offer =
           VaultKernel.APOffer(offerId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.stopPrank();

       // Setup for allocation
       vm.startPrank(bob);

       // Mock the previewRateAfterDeposit function
        vm.mockCall(
            address(targetVault), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
       vm.mockCall(
           address(targetVault),
           abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(uint256(tokenRateRequested-1))
           );
       // Allocate the offer
       vm.expectRevert(VaultKernel.OfferConditionsNotMet.selector);
       vaultKernel.allocateOffer(offer);

       // Verify allocation did not occur
       bytes32 offerHash = vaultKernel.getOfferHash(offer);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offerHash), quantity);
       assertEq(baseToken.balanceOf(address(alice)), quantity);
       assertEq(targetVault.balanceOf(alice), 0);

       vm.stopPrank();
   }

   function testAllocateOfferFrom0(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);
       vm.assume(tokenRateRequested > 1);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(vaultKernel), quantity);
       baseToken.approve(address(targetVault), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;

       // Create an offer
       uint256 offerId = vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultKernel.APOffer memory offer =
           VaultKernel.APOffer(offerId, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.stopPrank();

       // Setup for allocation
       vm.startPrank(bob);

       // Mock the previewRateAfterDeposit function
        vm.mockCall(
            address(targetVault), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
       vm.mockCall(
           address(targetVault),
           abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRateRequested)
           );
       // Allocate the offer
       vaultKernel.allocateOffer(offer);

       // Verify allocation
       bytes32 offerHash = vaultKernel.getOfferHash(offer);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offerHash), 0);
       assertEq(baseToken.balanceOf(address(targetVault)), quantity);
       assertEq(targetVault.balanceOf(alice), quantity);

       vm.stopPrank();
   }


   function testAllocateOfferFromVault(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
       vm.assume(quantity > 0);
       vm.assume(quantity <= type(uint256).max / quantity/2);
       vm.assume(timeToExpiry >= block.timestamp);
       vm.assume(block.timestamp <= timeToExpiry);
       vm.assume(tokenRateRequested > 1);

       baseToken.mint(alice, quantity);

       vm.startPrank(alice);

       baseToken.approve(address(vaultKernel), quantity);
       baseToken.approve(address(targetVault), quantity);
       baseToken.approve(address(fundingVault), quantity);
       ERC20(fundingVault).approve(address(vaultKernel), quantity);

       address[] memory tokensRequested = new address[](1);
       tokensRequested[0] = address(baseToken);
       uint256[] memory tokenRatesRequested = new uint256[](1);
       tokenRatesRequested[0] = tokenRateRequested;
       fundingVault.deposit(quantity, alice);

       uint256 offerId = vaultKernel.createAPOffer(address(targetVault), address(fundingVault), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultKernel.APOffer memory offer =
           VaultKernel.APOffer(offerId, address(targetVault), alice, address(fundingVault), timeToExpiry, tokensRequested, tokenRatesRequested);

       vm.stopPrank();

       vm.startPrank(bob);
        vm.mockCall(
            address(targetVault), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
       vm.mockCall(
           address(targetVault),
           abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRateRequested)
           );

       vaultKernel.allocateOffer(offer);

       bytes32 offerHash = vaultKernel.getOfferHash(offer);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offerHash), 0);
       assertEq(targetVault.balanceOf(alice), quantity);
       assertEq(fundingVault.balanceOf(alice), 0);

       vm.stopPrank();
   }

   function testAllocateOffers(uint256 quantity, uint256 timeToExpiry, uint256 tokenRateRequested) public {
        vm.assume(quantity > 0);
        vm.assume(quantity <= type(uint256).max / quantity/3);
        vm.assume(timeToExpiry >= block.timestamp);
        vm.assume(block.timestamp <= timeToExpiry);
        vm.assume(tokenRateRequested > 1);

        baseToken.mint(alice, 3*quantity);

       vm.startPrank(alice);
        baseToken.approve(address(vaultKernel), quantity*3);
        baseToken.approve(address(targetVault), quantity*3);

       address[] memory tokensRequested = new address[](3);
       tokensRequested[0] = address(baseToken);
       tokensRequested[1] = address(baseToken);
       tokensRequested[2] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](3);
        tokenRatesRequested[0] = tokenRateRequested;
        tokenRatesRequested[1] = tokenRateRequested;
        tokenRatesRequested[2] = tokenRateRequested;


       uint256 offer1Id =
           vaultKernel.createAPOffer(address(targetVault), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       uint256 offer2Id =
           vaultKernel.createAPOffer(address(targetVault2), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);
       uint256 offer3Id =
           vaultKernel.createAPOffer(address(targetVault3), address(0), quantity, timeToExpiry, tokensRequested, tokenRatesRequested);

       VaultKernel.APOffer memory offer1 =
           VaultKernel.APOffer(offer1Id, address(targetVault), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultKernel.APOffer memory offer2 =
           VaultKernel.APOffer(offer2Id, address(targetVault2), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
       VaultKernel.APOffer memory offer3 =
           VaultKernel.APOffer(offer3Id, address(targetVault3), alice, address(0), timeToExpiry, tokensRequested, tokenRatesRequested);
      
       VaultKernel.APOffer[] memory offers = new VaultKernel.APOffer[](3);

       bytes32 offer1Hash = vaultKernel.getOfferHash(offer1);
       bytes32 offer2Hash = vaultKernel.getOfferHash(offer2);
       bytes32 offer3Hash = vaultKernel.getOfferHash(offer3);

       offers[0] = offer1;
       offers[1] = offer2;
       offers[2] = offer3;

       // Mock the previewRateAfterDeposit function
        vm.mockCall(
            address(targetVault), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
       vm.mockCall(
           address(targetVault),
           abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRatesRequested[0])
           );
        vm.mockCall(
            address(targetVault2), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
       vm.mockCall(
           address(targetVault2),
           abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRatesRequested[1])
           );
        vm.mockCall(
            address(targetVault3), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
       vm.mockCall(
           address(targetVault3),
           abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), quantity),
           abi.encode(tokenRatesRequested[2])
           );

        uint256[] memory fillAmounts = new uint256[](3);
        fillAmounts[0] = type(uint256).max;
        fillAmounts[1] = type(uint256).max;
        fillAmounts[2] = type(uint256).max;
        vaultKernel.allocateOffers(offers, fillAmounts);

       //Verify all of the offers allocated
       assertEq(targetVault.balanceOf(alice), quantity);
       assertEq(targetVault2.balanceOf(alice), quantity);
       assertEq(targetVault3.balanceOf(alice), quantity);

       assertEq(vaultKernel.offerHashToRemainingQuantity(offer1Hash), 0);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offer2Hash), 0);
       assertEq(vaultKernel.offerHashToRemainingQuantity(offer3Hash), 0);

       assertEq(baseToken.balanceOf(address(alice)), 0);

       vm.stopPrank();
   }
}
