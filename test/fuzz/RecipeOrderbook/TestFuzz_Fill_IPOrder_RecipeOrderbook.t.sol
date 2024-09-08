// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_Fill_IPOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    address IP_ADDRESS = ALICE_ADDRESS;
    address FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    // Test for order expiration
    function testFuzz_RevertIf_OrderExpired(uint256 orderAmount, uint256 fillAmount, uint256 timeDelta, uint8 rewardStyle) external {
        // Bound the parameters to valid ranges
        rewardStyle = rewardStyle % 3; // Ensure valid enum value (0, 1, 2)
        orderAmount = (orderAmount % 1e30) + 1e6; // Bound to a reasonable range
        fillAmount = (fillAmount % orderAmount) + 1; // Ensure valid fill amount
        timeDelta = (timeDelta % 30 days) + 30 days + 1; // Ensure timeDelta is past the expiry

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle(rewardStyle));
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Simulate time passing beyond expiry
        vm.warp(block.timestamp + timeDelta);

        // Expect revert due to expiration
        vm.expectRevert(RecipeOrderbook.OrderExpired.selector);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    // Test for not enough remaining quantity
    function testFuzz_RevertIf_NotEnoughRemainingQuantity(uint256 orderAmount, uint256 fillAmount, uint8 rewardStyle) external {
        // Bound the parameters to valid ranges
        rewardStyle = rewardStyle % 3; // Ensure valid enum value (0, 1, 2)
        orderAmount = (orderAmount % 1e30) + 1e6; // Bound to a reasonable range
        fillAmount = orderAmount + (fillAmount % 1e18) + 1; // Ensure fill amount exceeds order amount

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle(rewardStyle));
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Expect revert due to insufficient remaining quantity
        vm.expectRevert(RecipeOrderbook.NotEnoughRemainingQuantity.selector);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    // Test for mismatched base asset
    function testFuzz_RevertIf_MismatchedBaseAsset(uint256 orderAmount, uint256 fillAmount, uint8 rewardStyle) external {
        // Bound the parameters to valid ranges
        rewardStyle = rewardStyle % 3; // Ensure valid enum value (0, 1, 2)
        orderAmount = (orderAmount % 1e30) + 1e6; // Bound to a reasonable range
        fillAmount = (fillAmount % orderAmount) + 1; // Ensure valid fill amount

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle(rewardStyle));
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Use a different vault with mismatched base asset
        address incorrectVault = address(new MockERC4626(mockIncentiveToken)); // Different asset

        // Expect revert due to mismatched base asset
        vm.expectRevert(RecipeOrderbook.MismatchedBaseAsset.selector);
        orderbook.fillIPOrder(orderId, fillAmount, incorrectVault, FRONTEND_FEE_RECIPIENT);
    }

    // Test for zero quantity fill
    function testFuzz_RevertIf_ZeroQuantityFill(uint256 orderAmount, uint8 rewardStyle) external {
        // Bound the parameters to valid ranges
        rewardStyle = rewardStyle % 3; // Ensure valid enum value (0, 1, 2)
        orderAmount = (orderAmount % 1e30) + 1e6; // Bound to a reasonable range

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle(rewardStyle));
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Expect revert due to zero quantity fill
        vm.expectRevert(RecipeOrderbook.CannotPlaceZeroQuantityOrder.selector);
        orderbook.fillIPOrder(orderId, 0, address(0), FRONTEND_FEE_RECIPIENT);
    }
}
