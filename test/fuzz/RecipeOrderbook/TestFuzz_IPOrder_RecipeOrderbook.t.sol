// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_IPOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_CreateIPOrder_NotPointsProgram(address _creator, uint256 _quantity, uint256 _expiry, uint256 _tokenCount) external prankModifier(_creator) {
        _tokenCount = _tokenCount % 5 + 1; // Limit token count between 1 and 5
        uint256 marketId = createMarket();
        address[] memory tokensOffered = new address[](_tokenCount);
        uint256[] memory tokenAmountsOffered = new uint256[](_tokenCount);

        // Generate random token addresses and amounts
        for (uint256 i = 0; i < _tokenCount; i++) {
            address tokenAddress = address(uint160(uint256(keccak256(abi.encodePacked(marketId, i)))));

            // Inject mock ERC20 bytecode into the token addresses
            MockERC20 mockToken = new MockERC20("Mock Token", "MKT");
            vm.etch(tokenAddress, address(mockToken).code);

            tokensOffered[i] = tokenAddress;
            tokenAmountsOffered[i] = (uint256(keccak256(abi.encodePacked(marketId, i)))) % 1000e18 + 1e18;
        }

        _quantity = _quantity % 1000e18 + 1e6; // Bound quantity
        _expiry = _expiry % 100_000 days + block.timestamp; // Bound expiry time

        // Mint and approve incentive tokens for creator
        for (uint256 i = 0; i < _tokenCount; i++) {
            MockERC20(tokensOffered[i]).mint(_creator, tokenAmountsOffered[i]);
            MockERC20(tokensOffered[i]).approve(address(orderbook), tokenAmountsOffered[i]);
        }

        // Calculate expected fees
        uint256[] memory protocolFeeAmount = new uint256[](_tokenCount);
        uint256[] memory frontendFeeAmount = new uint256[](_tokenCount);
        uint256[] memory incentiveAmount = new uint256[](_tokenCount);
        for (uint256 i = 0; i < _tokenCount; i++) {
            protocolFeeAmount[i] = tokenAmountsOffered[i].mulWadDown(orderbook.protocolFee());
            (,, uint256 frontendFee,,,) = orderbook.marketIDToWeirollMarket(marketId);
            frontendFeeAmount[i] = tokenAmountsOffered[i].mulWadDown(frontendFee);
            incentiveAmount[i] = tokenAmountsOffered[i] - protocolFeeAmount[i] - frontendFeeAmount[i];
        }

        // Expect the IPOrderCreated event to be emitted
        vm.expectEmit(true, true, true, true, address(orderbook));
        emit RecipeOrderbook.IPOrderCreated(
            0, // Expected order ID (starts at 0)
            marketId, // Market ID
            _creator, // IP address
            _expiry, // Expiry time
            tokensOffered, // Tokens offered
            tokenAmountsOffered, // Amounts offered
            _quantity // Total quantity
        );

        // MockERC20 should track calls to `transferFrom`
        for (uint256 i = 0; i < _tokenCount; i++) {
            vm.expectCall(
                tokensOffered[i],
                abi.encodeWithSelector(
                    ERC20.transferFrom.selector, _creator, address(orderbook), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]
                )
            );
        }

        // Create the IP order
        uint256 orderId = orderbook.createIPOrder(
            marketId, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            tokenAmountsOffered // Incentive amounts offered
        );

        // Assertions on the order
        assertEq(orderId, 0); // First IP order should have ID 0
        assertEq(orderbook.numIPOrders(), 1); // IP order count should be 1
        assertEq(orderbook.numLPOrders(), 0); // LP orders should remain 0

        for (uint256 i = 0; i < _tokenCount; i++) {
            uint256 frontendFeeStored = orderbook.getTokenToFrontendFeeAmountForIPOrder(orderId, tokensOffered[i]);
            uint256 incentiveAmountStored = orderbook.getTokenAmountsOfferedForIPOrder(orderId, tokensOffered[i]);

            // Assert that the values match expected values
            assertEq(frontendFeeStored, frontendFeeAmount[i]);
            assertEq(incentiveAmountStored, incentiveAmount[i]);

            // Check that the protocol fee is correctly accounted for
            assertEq(orderbook.feeClaimantToTokenToAmount(orderbook.protocolFeeClaimant(), tokensOffered[i]), protocolFeeAmount[i]);

            // Ensure the transfer was successful
            assertEq(MockERC20(tokensOffered[i]).balanceOf(address(orderbook)), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]);
        }
    }

    function testFuzz_RevertIf_CreateIPOrderWithNonExistentMarket(uint256 _marketId) external {
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.MarketDoesNotExist.selector));
        orderbook.createIPOrder(
            _marketId, // Non-existent market ID
            1000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOrderWithZeroQuantity(uint256 _quantity) external {
        _quantity = _quantity % 1e6;

        uint256 marketId = createMarket();

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.CannotPlaceZeroQuantityOrder.selector));
        orderbook.createIPOrder(
            marketId,
            _quantity, // Zero quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOrderWithExpiredOrder(uint256 _expiry, uint256 _blockTimestamp) external {
        _expiry = (_expiry % _blockTimestamp) + 1; // expiry always less than block timestamp
        vm.warp(_blockTimestamp); // set block timestamp

        uint256 marketId = createMarket();

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.CannotPlaceExpiredOrder.selector));
        orderbook.createIPOrder(
            marketId,
            1000e18, // Quantity
            _expiry, // Expired timestamp
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOrderWithMismatchedTokenArrays(uint8 _tokensOfferedLen, uint8 _tokenAmountsOfferedLen) external {
        vm.assume(_tokensOfferedLen != _tokenAmountsOfferedLen);

        uint256 marketId = createMarket();

        address[] memory tokensOffered = new address[](_tokensOfferedLen);
        uint256[] memory tokenAmountsOffered = new uint256[](_tokenAmountsOfferedLen);

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.ArrayLengthMismatch.selector));
        orderbook.createIPOrder(
            marketId,
            1000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            tokensOffered, // Mismatched arrays
            tokenAmountsOffered
        );
    }
}
