// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";
import "src/WrappedVault.sol";

import { MockERC20 } from "../../mocks/MockERC20.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_IPOfferCreation_RecipeKernel is RecipeKernelTestBase {
    using FixedPointMathLib for uint256;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateIPOffer_ForTokens() external prankModifier(ALICE_ADDRESS) {
        uint256 marketId = createMarket();

        // Handle minting incentive token to the IP's address
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;
        mockIncentiveToken.mint(ALICE_ADDRESS, 1000e18);
        mockIncentiveToken.approve(address(recipeKernel), 1000e18);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited
        uint256 expiry = block.timestamp + 1 days; // Offer expires in 1 day

        // Calculate expected fees
        (,, uint256 frontendFee,,,) = recipeKernel.marketIDToWeirollMarket(marketId);
        uint256 incentiveAmount = incentiveAmountsOffered[0].divWadDown(1e18 + recipeKernel.protocolFee() + frontendFee);
        uint256 protocolFeeAmount = incentiveAmount.mulWadDown(recipeKernel.protocolFee());
        uint256 frontendFeeAmount = incentiveAmount.mulWadDown(frontendFee);

        // Expect the IPOfferCreated event to be emitted
        vm.expectEmit(false, false, false, false, address(recipeKernel));
        emit RecipeKernelBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            marketId, // Market ID
            quantity, // Total quantity
            tokensOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            expiry // Expiry time
        );

        // MockERC20 should track calls to `transferFrom`
        vm.expectCall(
            address(mockIncentiveToken),
            abi.encodeWithSelector(ERC20.transferFrom.selector, ALICE_ADDRESS, address(recipeKernel), protocolFeeAmount + frontendFeeAmount + incentiveAmount)
        );

        // Create the IP offer
        uint256 offerId = recipeKernel.createIPOffer(
            marketId, // Referencing the created market
            quantity, // Total input token amount
            expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );

        // Assertions on the offer
        assertEq(offerId, 0); // First IP offer should have ID 0
        assertEq(recipeKernel.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeKernel.numAPOffers(), 0); // AP offers should remain 0

        // Use the helper function to retrieve values from storage
        uint256 frontendFeeStored = recipeKernel.getIncentiveToFrontendFeeAmountForIPOffer(offerId, tokensOffered[0]);
        uint256 protocolFeeAmountStored = recipeKernel.getIncentiveToProtocolFeeAmountForIPOffer(offerId, tokensOffered[0]);
        uint256 incentiveAmountStored = recipeKernel.getIncentiveAmountsOfferedForIPOffer(offerId, tokensOffered[0]);

        // Assert that the values match expected values
        assertEq(frontendFeeStored, frontendFeeAmount);
        assertEq(incentiveAmountStored, incentiveAmount);
        assertEq(protocolFeeAmountStored, protocolFeeAmount);

        // Ensure the transfer was successful
        assertEq(MockERC20(address(mockIncentiveToken)).balanceOf(address(recipeKernel)), protocolFeeAmount + frontendFeeAmount + incentiveAmount);
    }

    function test_CreateIPOffer_ForPointsProgram() external {
        uint256 marketId = createMarket();

        Points points = pointsFactory.createPointsProgram("POINTS", "PTS", 18, BOB_ADDRESS);
        vm.startPrank(BOB_ADDRESS);
        points.addAllowedIP(ALICE_ADDRESS);
        vm.stopPrank();

        // Handle minting incentive token to the IP's address
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(points);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited
        uint256 expiry = block.timestamp + 1 days; // Offer expires in 1 day

        // Calculate expected fees
        (,, uint256 frontendFee,,,) = recipeKernel.marketIDToWeirollMarket(marketId);
        uint256 incentiveAmount = incentiveAmountsOffered[0].divWadDown(1e18 + recipeKernel.protocolFee() + frontendFee);
        uint256 protocolFeeAmount = incentiveAmount.mulWadDown(recipeKernel.protocolFee());
        uint256 frontendFeeAmount = incentiveAmount.mulWadDown(frontendFee);

        vm.expectEmit(false, false, false, false, address(recipeKernel));
        emit RecipeKernelBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            marketId, // Market ID
            quantity, // Total quantity
            tokensOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            expiry // Expiry time
        );

        vm.startPrank(ALICE_ADDRESS);
        // Create the IP offer
        uint256 offerId = recipeKernel.createIPOffer(
            marketId, // Referencing the created market
            quantity, // Total input token amount
            expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
        vm.stopPrank();

        // Assertions on the offer
        assertEq(offerId, 0); // First IP offer should have ID 0
        assertEq(recipeKernel.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeKernel.numAPOffers(), 0); // AP offers should remain 0

        // Use the helper function to retrieve values from storage
        uint256 frontendFeeStored = recipeKernel.getIncentiveToFrontendFeeAmountForIPOffer(offerId, tokensOffered[0]);
        uint256 protocolFeeAmountStored = recipeKernel.getIncentiveToProtocolFeeAmountForIPOffer(offerId, tokensOffered[0]);
        uint256 incentiveAmountStored = recipeKernel.getIncentiveAmountsOfferedForIPOffer(offerId, tokensOffered[0]);

        // Assert that the values match expected values
        assertEq(frontendFeeStored, frontendFeeAmount);
        assertEq(incentiveAmountStored, incentiveAmount);
        assertEq(protocolFeeAmountStored, protocolFeeAmount);
    }

    function test_RevertIf_CreateIPOfferWithNonExistentMarket() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.MarketDoesNotExist.selector));
        recipeKernel.createIPOffer(
            0, // Non-existent market ID
            100_000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function test_RevertIf_CreateIPOfferWithExpiredOffer() external {
        vm.warp(1_231_006_505); // set block timestamp
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.CannotPlaceExpiredOffer.selector));
        recipeKernel.createIPOffer(
            marketId,
            100_000e18, // Quantity
            block.timestamp - 1 seconds, // Expired timestamp
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function test_RevertIf_CreateIPOfferWithZeroQuantity() external {
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.CannotPlaceZeroQuantityOffer.selector));
        recipeKernel.createIPOffer(
            marketId,
            0, // Zero quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function test_RevertIf_CreateIPOfferWithMismatchedTokenArrays() external {
        uint256 marketId = createMarket();

        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory incentiveAmountsOffered = new uint256[](2);
        incentiveAmountsOffered[0] = 1000e18;

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.ArrayLengthMismatch.selector));
        recipeKernel.createIPOffer(
            marketId,
            100_000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            tokensOffered, // Mismatched arrays
            incentiveAmountsOffered
        );
    }
}
