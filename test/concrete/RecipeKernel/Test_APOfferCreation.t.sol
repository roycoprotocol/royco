// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";
import { MockERC4626 } from "../../mocks/MockERC4626.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";

contract Test_APOfferCreation_RecipeKernel is RecipeKernelTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateAPOffer() external prankModifier(ALICE_ADDRESS) {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited
        uint256 expiry = block.timestamp + 1 days; // Offer expires in 1 day

        // Expect the APOfferCreated event to be emitted
        vm.expectEmit(true, true, true, false, address(recipeKernel));
        emit RecipeKernelBase.APOfferCreated(
            0, // Expected offer ID (starts at 0)
            marketId, // Market ID
            address(0), // No funding vault
            quantity,
            tokensRequested, // Tokens requested
            tokenAmountsRequested, // Amounts requested,
            expiry // Expiry time
        );

        // Create the AP offer
        uint256 offerId = recipeKernel.createAPOffer(
            marketId, // Referencing the created market
            address(0), // No funding vault
            quantity, // Total input token amount
            expiry, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );

        assertEq(offerId, 0); // First AP offer should have ID 0
        assertEq(recipeKernel.numAPOffers(), 1); // AP offer count should be 1
        assertEq(recipeKernel.numIPOffers(), 0); // IP offers should remain 0

        // Check hash is added correctly and quantity can be retrieved from mapping
        bytes32 offerHash = recipeKernel.getOfferHash(
            RecipeKernelBase.APOffer(0, marketId, ALICE_ADDRESS, address(0), quantity, expiry, tokensRequested, tokenAmountsRequested)
        );

        assertEq(recipeKernel.offerHashToRemainingQuantity(offerHash), quantity); // Ensure the correct quantity is stored
    }

    function test_RevertIf_CreateAPOfferWithNonExistentMarket() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.MarketDoesNotExist.selector));
        recipeKernel.createAPOffer(
            0, // Non-existent market ID
            address(0),
            100_000e18,
            block.timestamp + 1 days,
            new address[](1),
            new uint256[](1)
        );
    }

    function test_RevertIf_CreateAPOfferWithExpiredOffer() external {
        vm.warp(1_231_006_505); // set block timestamp
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.CannotPlaceExpiredOffer.selector));
        recipeKernel.createAPOffer(
            marketId,
            address(0),
            100_000e18,
            block.timestamp - 1 seconds, // Expired timestamp
            new address[](1),
            new uint256[](1)
        );
    }

    function test_RevertIf_CreateAPOfferWithZeroQuantity() external {
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.CannotPlaceZeroQuantityOffer.selector));
        recipeKernel.createAPOffer(
            marketId,
            address(0),
            0, // Zero quantity
            block.timestamp + 1 days,
            new address[](1),
            new uint256[](1)
        );
    }

    function test_RevertIf_CreateAPOfferWithMismatchedTokenArrays() external {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        uint256[] memory tokenAmountsRequested = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.ArrayLengthMismatch.selector));
        recipeKernel.createAPOffer(marketId, address(0), 100_000e18, block.timestamp + 1 days, tokensRequested, tokenAmountsRequested);
    }

    function test_RevertIf_CreateAPOfferWithMismatchedBaseAsset() external {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        MockERC4626 incentiveVault = new MockERC4626(mockIncentiveToken);

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.MismatchedBaseAsset.selector));
        recipeKernel.createAPOffer(
            marketId,
            address(incentiveVault), // Funding vault with mismatched base asset
            100_000e18,
            block.timestamp + 1 days,
            tokensRequested,
            tokenAmountsRequested
        );
    }
}
