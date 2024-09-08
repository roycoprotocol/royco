// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/WeirollWallet.sol";
import "../../../src/RecipeOrderbook.sol";
import "../../../src/PointsFactory.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { RoycoTestBase } from "../RoycoTestBase.sol";
import { RecipeUtils } from "./RecipeUtils.sol";

contract RecipeOrderbookTestBase is RoycoTestBase, RecipeUtils {
    using FixedPointMathLib for uint256;

    // Fees set in orderbook constructor
    uint256 initialProtocolFee;
    uint256 initialMinimumFrontendFee;

    function setUpRecipeOrderbookTests(uint256 _initialProtocolFee, uint256 _initialMinimumFrontendFee) public {
        setupBaseEnvironment();

        initialProtocolFee = _initialProtocolFee;
        initialMinimumFrontendFee = _initialMinimumFrontendFee;

        orderbook = new RecipeOrderbook(
            address(weirollImplementation),
            initialProtocolFee,
            initialMinimumFrontendFee,
            OWNER_ADDRESS, // fee claimant
            address(pointsFactory)
        );
    }

    function createMarket() public returns (uint256 marketId) {
        // Generate random market parameters within valid constraints
        uint256 lockupTime = 1 hours + (uint256(keccak256(abi.encodePacked(block.timestamp))) % 29 days); // Lockup time between 1 hour and 30 days
        uint256 frontendFee = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 1e17) + initialMinimumFrontendFee;
        // Generate random reward style (valid values 0, 1, 2)
        RewardStyle rewardStyle = RewardStyle(uint8(uint256(keccak256(abi.encodePacked(block.timestamp))) % 3));
        // Create market
        marketId = orderbook.createMarket(address(mockLiquidityToken), lockupTime, frontendFee, NULL_RECIPE, NULL_RECIPE, rewardStyle);
    }

    function createMarket(RecipeOrderbook.Recipe memory _depositRecipe, RecipeOrderbook.Recipe memory _withdrawRecipe) public returns (uint256 marketId) {
        // Generate random market parameters within valid constraints
        uint256 lockupTime = 1 hours + (uint256(keccak256(abi.encodePacked(block.timestamp))) % 29 days); // Lockup time between 1 hour and 30 days
        uint256 frontendFee = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 1e17) + initialMinimumFrontendFee;
        // Generate random reward style (valid values 0, 1, 2)
        RewardStyle rewardStyle = RewardStyle(uint8(uint256(keccak256(abi.encodePacked(block.timestamp))) % 3));
        // Create market
        marketId = orderbook.createMarket(address(mockLiquidityToken), lockupTime, frontendFee, _depositRecipe, _withdrawRecipe, rewardStyle);
    }

    function createIPOrder_WithTokens(
        uint256 _targetMarketID,
        uint256 _quantity,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (uint256 orderId)
    {
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsOffered = new uint256[](1);
        tokenAmountsOffered[0] = 100e18;

        mockIncentiveToken.mint(_ipAddress, 100e18);
        mockIncentiveToken.approve(address(orderbook), 100e18);

        orderId = orderbook.createIPOrder(
            _targetMarketID, // Referencing the created market
            _quantity, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            tokenAmountsOffered // Incentive amounts offered
        );
    }

    function createIPOrder_WithPoints(
        uint256 _targetMarketID,
        uint256 _quantity,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (uint256 orderId, Points points)
    {
        address[] memory tokensOffered = new address[](1);
        uint256[] memory tokenAmountsOffered = new uint256[](1);

        string memory name = "POINTS";
        string memory symbol = "PTS";

        // Create a new Points program
        points = PointsFactory(orderbook.POINTS_FACTORY()).createPointsProgram(name, symbol, 18, _ipAddress, ERC4626i(address(mockVault)), orderbook);

        // Allow _ipAddress to mint points in the Points program
        points.addAllowedIP(_ipAddress);

        // Add the Points program to the tokensOffered array
        tokensOffered[0] = address(points);
        tokenAmountsOffered[0] = 100e18;

        orderId = orderbook.createIPOrder(
            _targetMarketID, // Referencing the created market
            _quantity, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            tokenAmountsOffered // Incentive amounts offered
        );
    }

    function calculateIPOrderExpectedIncentiveAndFrontendFee(
        uint256 orderId,
        uint256 orderAmount,
        uint256 fillAmount,
        address tokenOffered
    )
        internal
        view
        returns (uint256 fillPercentage, uint256 frontendFeeAmount, uint256 incentiveAmount)
    {
        fillPercentage = fillAmount.divWadDown(orderAmount);
        // Fees are taken as a percentage of the promised amounts
        frontendFeeAmount = orderbook.getTokenToFrontendFeeAmountForIPOrder(orderId, tokenOffered).mulWadDown(fillPercentage);
        incentiveAmount = orderbook.getTokenAmountsOfferedForIPOrder(orderId, tokenOffered).mulWadDown(fillPercentage);
    }
}
