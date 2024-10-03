// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/WeirollWallet.sol";
import "test/mocks/MockRecipeKernel.sol";
import "../../../src/PointsFactory.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { RoycoTestBase } from "../RoycoTestBase.sol";
import { RecipeUtils } from "./RecipeUtils.sol";

contract RecipeKernelTestBase is RoycoTestBase, RecipeUtils {
    using FixedPointMathLib for uint256;

    // Fees set in RecipeKernel constructor
    uint256 initialProtocolFee;
    uint256 initialMinimumFrontendFee;

    function setUpRecipeKernelTests(uint256 _initialProtocolFee, uint256 _initialMinimumFrontendFee) public {
        setupBaseEnvironment();

        initialProtocolFee = _initialProtocolFee;
        initialMinimumFrontendFee = _initialMinimumFrontendFee;

        recipeKernel = new MockRecipeKernel(
            address(weirollImplementation),
            initialProtocolFee,
            initialMinimumFrontendFee,
            OWNER_ADDRESS, // fee claimant
            address(pointsFactory)
        );

        vm.startPrank(POINTS_FACTORY_OWNER_ADDRESS);
        pointsFactory.addRecipeKernel(address(recipeKernel));
        vm.stopPrank();
    }

    function createMarket() public returns (uint256 marketId) {
        // Generate random market parameters within valid constraints
        uint256 lockupTime = 1 hours + (uint256(keccak256(abi.encodePacked(block.timestamp))) % 29 days); // Lockup time between 1 hour and 30 days
        uint256 frontendFee = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 1e17) + initialMinimumFrontendFee;
        // Generate random reward style (valid values 0, 1, 2)
        RewardStyle rewardStyle = RewardStyle(uint8(uint256(keccak256(abi.encodePacked(block.timestamp))) % 3));
        // Create market
        marketId = recipeKernel.createMarket(address(mockLiquidityToken), lockupTime, frontendFee, NULL_RECIPE, NULL_RECIPE, rewardStyle);
    }

    function createMarket(RecipeKernelBase.Recipe memory _depositRecipe, RecipeKernelBase.Recipe memory _withdrawRecipe) public returns (uint256 marketId) {
        // Generate random market parameters within valid constraints
        uint256 lockupTime = 1 hours + (uint256(keccak256(abi.encodePacked(block.timestamp))) % 29 days); // Lockup time between 1 hour and 30 days
        uint256 frontendFee = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 1e17) + initialMinimumFrontendFee;
        // Generate random reward style (valid values 0, 1, 2)
        RewardStyle rewardStyle = RewardStyle(uint8(uint256(keccak256(abi.encodePacked(block.timestamp))) % 3));
        // Create market
        marketId = recipeKernel.createMarket(address(mockLiquidityToken), lockupTime, frontendFee, _depositRecipe, _withdrawRecipe, rewardStyle);
    }

    function createIPOffer_WithTokens(
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
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        mockIncentiveToken.mint(_ipAddress, 1000e18);
        mockIncentiveToken.approve(address(recipeKernel), 1000e18);

        orderId = recipeKernel.createIPOffer(
            _targetMarketID, // Referencing the created market
            _quantity, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
    }

    function createIPOffer_WithTokens(
        uint256 _targetMarketID,
        uint256 _quantity,
        uint256 _expiry,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (uint256 orderId)
    {
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        mockIncentiveToken.mint(_ipAddress, 1000e18);
        mockIncentiveToken.approve(address(recipeKernel), 1000e18);

        orderId = recipeKernel.createIPOffer(
            _targetMarketID, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
    }

    function createAPOffer_ForTokens(
        uint256 _targetMarketID,
        address _fundingVault,
        uint256 _quantity,
        address _apAddress
    )
        public
        prankModifier(_apAddress)
        returns (uint256 orderId, RecipeKernelBase.APOffer memory order)
    {
        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        orderId = recipeKernel.createAPOffer(
            _targetMarketID, // Referencing the created market
            _fundingVault, // Address of funding vault
            _quantity, // Total input token amount
            30 days, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );

        order = RecipeKernelBase.APOffer(orderId, _targetMarketID, _apAddress, _fundingVault, _quantity, 30 days, tokensRequested, tokenAmountsRequested);
    }

    function createAPOffer_ForTokens(
        uint256 _targetMarketID,
        address _fundingVault,
        uint256 _quantity,
        uint256 _expiry,
        address _apAddress
    )
        public
        prankModifier(_apAddress)
        returns (uint256 orderId, RecipeKernelBase.APOffer memory order)
    {
        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        orderId = recipeKernel.createAPOffer(
            _targetMarketID, // Referencing the created market
            _fundingVault, // Address of funding vault
            _quantity, // Total input token amount
            _expiry, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );

        order = RecipeKernelBase.APOffer(orderId, _targetMarketID, _apAddress, _fundingVault, _quantity, _expiry, tokensRequested, tokenAmountsRequested);
    }

    function createAPOffer_ForPoints(
        uint256 _targetMarketID,
        address _fundingVault,
        uint256 _quantity,
        address _apAddress,
        address _ipAddress
    )
        public
        returns (uint256 orderId, RecipeKernelBase.APOffer memory order, Points points)
    {
        address[] memory tokensRequested = new address[](1);
        uint256[] memory tokenAmountsRequested = new uint256[](1);

        string memory name = "POINTS";
        string memory symbol = "PTS";

        vm.startPrank(_ipAddress);
        // Create a new Points program
        points = PointsFactory(recipeKernel.POINTS_FACTORY()).createPointsProgram(name, symbol, 18, _ipAddress);

        // Allow _ipAddress to mint points in the Points program
        points.addAllowedIP(_ipAddress);
        vm.stopPrank();

        // Add the Points program to the tokensOffered array
        tokensRequested[0] = address(points);
        tokenAmountsRequested[0] = 1000e18;

        vm.startPrank(_apAddress);
        orderId = recipeKernel.createAPOffer(
            _targetMarketID, // Referencing the created market
            _fundingVault, // Address of funding vault
            _quantity, // Total input token amount
            30 days, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );
        vm.stopPrank();
        order = RecipeKernelBase.APOffer(orderId, _targetMarketID, _apAddress, _fundingVault, _quantity, 30 days, tokensRequested, tokenAmountsRequested);
    }

    function createIPOffer_WithPoints(
        uint256 _targetMarketID,
        uint256 _quantity,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (uint256 orderId, Points points)
    {
        address[] memory tokensOffered = new address[](1);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);

        string memory name = "POINTS";
        string memory symbol = "PTS";

        // Create a new Points program
        points = PointsFactory(recipeKernel.POINTS_FACTORY()).createPointsProgram(name, symbol, 18, _ipAddress);

        // Allow _ipAddress to mint points in the Points program
        points.addAllowedIP(_ipAddress);

        // Add the Points program to the tokensOffered array
        tokensOffered[0] = address(points);
        incentiveAmountsOffered[0] = 1000e18;

        orderId = recipeKernel.createIPOffer(
            _targetMarketID, // Referencing the created market
            _quantity, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
    }

    function calculateIPOfferExpectedIncentiveAndFrontendFee(
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
        protocolFeeAmount = recipeKernel.getIncentiveToProtocolFeeAmountForIPOffer(orderId, tokenOffered).mulWadDown(fillPercentage);
        frontendFeeAmount = recipeKernel.getIncentiveToFrontendFeeAmountForIPOffer(orderId, tokenOffered).mulWadDown(fillPercentage);
        incentiveAmount = recipeKernel.getIncentiveAmountsOfferedForIPOffer(orderId, tokenOffered).mulWadDown(fillPercentage);
    }

    function calculateAPOfferExpectedIncentiveAndFrontendFee(
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
