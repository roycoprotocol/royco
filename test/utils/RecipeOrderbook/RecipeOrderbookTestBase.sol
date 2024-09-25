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

        vm.startPrank(POINTS_FACTORY_OWNER_ADDRESS);
        pointsFactory.addRecipeOrderbook(address(orderbook));
        vm.stopPrank();
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
        tokenAmountsOffered[0] = 1000e18;

        mockIncentiveToken.mint(_ipAddress, 1000e18);
        mockIncentiveToken.approve(address(orderbook), 1000e18);

        orderId = orderbook.createIPOrder(
            _targetMarketID, // Referencing the created market
            _quantity, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            tokenAmountsOffered // Incentive amounts offered
        );
    }

    function createAPOrder_ForTokens(
        uint256 _targetMarketID,
        address _fundingVault,
        uint256 _quantity,
        address _apAddress
    )
        public
        prankModifier(_apAddress)
        returns (uint256 orderId, RecipeOrderbook.APOrder memory order)
    {
        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        orderId = orderbook.createAPOrder(
            _targetMarketID, // Referencing the created market
            _fundingVault, // Address of funding vault
            _quantity, // Total input token amount
            30 days, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );

        order = RecipeOrderbook.APOrder(orderId, _targetMarketID, _apAddress, _fundingVault, _quantity, 30 days, tokensRequested, tokenAmountsRequested);
    }

    function createAPOrder_ForPoints(
        uint256 _targetMarketID,
        address _fundingVault,
        uint256 _quantity,
        address _apAddress,
        address _ipAddress
    )
        public
        returns (uint256 orderId, RecipeOrderbook.APOrder memory order, Points points)
    {
        address[] memory tokensRequested = new address[](1);
        uint256[] memory tokenAmountsRequested = new uint256[](1);

        string memory name = "POINTS";
        string memory symbol = "PTS";

        vm.startPrank(_ipAddress);
        // Create a new Points program
        points = PointsFactory(orderbook.POINTS_FACTORY()).createPointsProgram(name, symbol, 18, _ipAddress);

        // Allow _ipAddress to mint points in the Points program
        points.addAllowedIP(_ipAddress);
        vm.stopPrank();

        // Add the Points program to the tokensOffered array
        tokensRequested[0] = address(points);
        tokenAmountsRequested[0] = 1000e18;

        vm.startPrank(_apAddress);
        orderId = orderbook.createAPOrder(
            _targetMarketID, // Referencing the created market
            _fundingVault, // Address of funding vault
            _quantity, // Total input token amount
            30 days, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );
        vm.stopPrank();
        order = RecipeOrderbook.APOrder(orderId, _targetMarketID, _apAddress, _fundingVault, _quantity, 30 days, tokensRequested, tokenAmountsRequested);
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
        points = PointsFactory(orderbook.POINTS_FACTORY()).createPointsProgram(name, symbol, 18, _ipAddress);

        // Allow _ipAddress to mint points in the Points program
        points.addAllowedIP(_ipAddress);

        // Add the Points program to the tokensOffered array
        tokensOffered[0] = address(points);
        tokenAmountsOffered[0] = 1000e18;

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
        returns (uint256 fillPercentage, uint256 protocolFeeAmount, uint256 frontendFeeAmount, uint256 incentiveAmount)
    {
        fillPercentage = fillAmount.divWadDown(orderAmount);
        // Fees are taken as a percentage of the promised amounts
        protocolFeeAmount = orderbook.getTokenToProtocolFeeAmountForIPOrder(orderId, tokenOffered).mulWadDown(fillPercentage);
        frontendFeeAmount = orderbook.getTokenToFrontendFeeAmountForIPOrder(orderId, tokenOffered).mulWadDown(fillPercentage);
        incentiveAmount = orderbook.getTokenAmountsOfferedForIPOrder(orderId, tokenOffered).mulWadDown(fillPercentage);
    }

    function calculateAPOrderExpectedIncentiveAndFrontendFee(
        uint256 protocolFee,
        uint256 frontendFee,
        uint256 orderAmount,
        uint256 fillAmount,
        uint256 tokenAmountRequested
    )
        internal
        pure
        returns (uint256 fillPercentage, uint256 frontendFeeAmount, uint256 protocolFeeAmount, uint256 incentiveAmount)
    {
        fillPercentage = fillAmount.divWadDown(orderAmount);
        incentiveAmount = tokenAmountRequested.mulWadDown(fillPercentage);
        protocolFeeAmount = incentiveAmount.mulWadDown(protocolFee);
        frontendFeeAmount = incentiveAmount.mulWadDown(frontendFee);
    }
}
