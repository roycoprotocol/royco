// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/WeirollWallet.sol";
import "test/mocks/MockRecipeMarketHub.sol";
import "../../../src/PointsFactory.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { div } from "prb-math/sd59x18/Math.sol";
import { wrap, unwrap } from "prb-math/sd59x18/Casting.sol";

import { RoycoTestBase } from "../RoycoTestBase.sol";
import { RecipeUtils } from "./RecipeUtils.sol";

import { GradualDutchAuction } from "src/gda/GDA.sol";

contract RecipeMarketHubTestBase is RoycoTestBase, RecipeUtils {
    using FixedPointMathLib for uint256;

    // Fees set in RecipeMarketHub constructor
    uint256 initialProtocolFee;
    uint256 initialMinimumFrontendFee;

    function setUpRecipeMarketHubTests(uint256 _initialProtocolFee, uint256 _initialMinimumFrontendFee) public {
        setupBaseEnvironment();

        initialProtocolFee = _initialProtocolFee;
        initialMinimumFrontendFee = _initialMinimumFrontendFee;

        recipeMarketHub = new MockRecipeMarketHub(
            address(weirollImplementation),
            initialProtocolFee,
            initialMinimumFrontendFee,
            OWNER_ADDRESS, // fee claimant
            address(pointsFactory)
        );

        vm.startPrank(POINTS_FACTORY_OWNER_ADDRESS);
        pointsFactory.addRecipeMarketHub(address(recipeMarketHub));
        vm.stopPrank();
    }

    function createMarket() public returns (bytes32 marketHash) {
        // Generate random market parameters within valid constraints
        uint256 lockupTime = 1 hours + (uint256(keccak256(abi.encodePacked(block.timestamp))) % 29 days); // Lockup time between 1 hour and 30 days
        uint256 frontendFee = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 1e17) + initialMinimumFrontendFee;
        // Generate random reward style (valid values 0, 1, 2)
        RewardStyle rewardStyle = RewardStyle(uint8(uint256(keccak256(abi.encodePacked(block.timestamp))) % 3));
        // Create market
        marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), lockupTime, frontendFee, NULL_RECIPE, NULL_RECIPE, rewardStyle);
    }

    function createMarket(
        RecipeMarketHubBase.Recipe memory _depositRecipe,
        RecipeMarketHubBase.Recipe memory _withdrawRecipe
    )
        public
        returns (bytes32 marketHash)
    {
        // Generate random market parameters within valid constraints
        uint256 lockupTime = 1 hours + (uint256(keccak256(abi.encodePacked(block.timestamp))) % 29 days); // Lockup time between 1 hour and 30 days
        uint256 frontendFee = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 1e17) + initialMinimumFrontendFee;
        // Generate random reward style (valid values 0, 1, 2)
        RewardStyle rewardStyle = RewardStyle(uint8(uint256(keccak256(abi.encodePacked(block.timestamp))) % 3));
        // Create market
        marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), lockupTime, frontendFee, _depositRecipe, _withdrawRecipe, rewardStyle);
    }

    function createIPOffer_WithTokens(
        bytes32 _targetMarketHash,
        uint256 _quantity,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (bytes32 offerHash)
    {
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        mockIncentiveToken.mint(_ipAddress, 1000e18);
        mockIncentiveToken.approve(address(recipeMarketHub), 1000e18);

        offerHash = recipeMarketHub.createIPOffer(
            _targetMarketHash, // Referencing the created market
            _quantity, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
    }

    function createIPGdaOffer_WithTokens(
        bytes32 _targetMarketHash,
        uint256 _quantity,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (bytes32 offerHash)
    {
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        RecipeMarketHubBase.GDAParams memory gdaParams;
        gdaParams.initialDiscountMultiplier = 10 * 1e18 / 100;
        gdaParams.decayRate = unwrap(div(wrap(SafeCastLib.toInt256(1)), wrap(SafeCastLib.toInt256(2))));
        gdaParams.emissionRate = SafeCastLib.toInt256(1);
        gdaParams.lastAuctionStartTime = 0;

        mockIncentiveToken.mint(_ipAddress, 1000e18);
        mockIncentiveToken.approve(address(recipeMarketHub), 1000e18);

        offerHash = recipeMarketHub.createIPGdaOffer(
            _targetMarketHash, // Referencing the created market
            _quantity, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered, // Incentive amounts offered
            gdaParams
        );
    }

    function createIPOffer_WithTokens(
        bytes32 _targetMarketHash,
        uint256 _quantity,
        uint256 _expiry,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (bytes32 offerHash)
    {
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        mockIncentiveToken.mint(_ipAddress, 1000e18);
        mockIncentiveToken.approve(address(recipeMarketHub), 1000e18);

        offerHash = recipeMarketHub.createIPOffer(
            _targetMarketHash, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
    }

    function createIPGdaOffer_WithTokens(
        bytes32 _targetMarketHash,
        uint256 _quantity,
        uint256 _expiry,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (bytes32 offerHash)
    {
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        RecipeMarketHubBase.GDAParams memory gdaParams;
        gdaParams.initialDiscountMultiplier = 10 * 1e18 / 100;
        gdaParams.decayRate = unwrap(div(wrap(SafeCastLib.toInt256(1)), wrap(SafeCastLib.toInt256(2))));
        gdaParams.emissionRate = SafeCastLib.toInt256(1);
        gdaParams.lastAuctionStartTime = 0;

        mockIncentiveToken.mint(_ipAddress, 1000e18);
        mockIncentiveToken.approve(address(recipeMarketHub), 1000e18);

        offerHash = recipeMarketHub.createIPGdaOffer(
            _targetMarketHash, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered, // Incentive amounts offered
            gdaParams
        );
    }

    function createAPOffer_ForTokens(
        bytes32 _targetMarketHash,
        address _fundingVault,
        uint256 _quantity,
        address _apAddress
    )
        public
        prankModifier(_apAddress)
        returns (bytes32 offerHash, RecipeMarketHubBase.APOffer memory offer)
    {
        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        offerHash = recipeMarketHub.createAPOffer(
            _targetMarketHash, // Referencing the created market
            _fundingVault, // Address of funding vault
            _quantity, // Total input token amount
            30 days, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );

        offer = RecipeMarketHubBase.APOffer(
            recipeMarketHub.numAPOffers() - 1, _targetMarketHash, _apAddress, _fundingVault, _quantity, 30 days, tokensRequested, tokenAmountsRequested
        );
    }

    function createAPOffer_ForTokens(
        bytes32 _targetMarketHash,
        address _fundingVault,
        uint256 _quantity,
        uint256 _expiry,
        address _apAddress
    )
        public
        prankModifier(_apAddress)
        returns (bytes32 offerHash, RecipeMarketHubBase.APOffer memory offer)
    {
        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        offerHash = recipeMarketHub.createAPOffer(
            _targetMarketHash, // Referencing the created market
            _fundingVault, // Address of funding vault
            _quantity, // Total input token amount
            _expiry, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );

        offer = RecipeMarketHubBase.APOffer(
            recipeMarketHub.numAPOffers() - 1, _targetMarketHash, _apAddress, _fundingVault, _quantity, _expiry, tokensRequested, tokenAmountsRequested
        );
    }

    function createAPOffer_ForPoints(
        bytes32 _targetMarketHash,
        address _fundingVault,
        uint256 _quantity,
        address _apAddress,
        address _ipAddress
    )
        public
        returns (bytes32 offerHash, RecipeMarketHubBase.APOffer memory offer, Points points)
    {
        address[] memory tokensRequested = new address[](1);
        uint256[] memory tokenAmountsRequested = new uint256[](1);

        string memory name = "POINTS";
        string memory symbol = "PTS";

        vm.startPrank(_ipAddress);
        // Create a new Points program
        points = PointsFactory(recipeMarketHub.POINTS_FACTORY()).createPointsProgram(name, symbol, 18, _ipAddress);

        // Allow _ipAddress to mint points in the Points program
        points.addAllowedIP(_ipAddress);
        vm.stopPrank();

        // Add the Points program to the tokensOffered array
        tokensRequested[0] = address(points);
        tokenAmountsRequested[0] = 1000e18;

        vm.startPrank(_apAddress);
        offerHash = recipeMarketHub.createAPOffer(
            _targetMarketHash, // Referencing the created market
            _fundingVault, // Address of funding vault
            _quantity, // Total input token amount
            30 days, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );
        vm.stopPrank();
        offer = RecipeMarketHubBase.APOffer(
            recipeMarketHub.numAPOffers() - 1, _targetMarketHash, _apAddress, _fundingVault, _quantity, 30 days, tokensRequested, tokenAmountsRequested
        );
    }

    function createIPOffer_WithPoints(
        bytes32 _targetMarketHash,
        uint256 _quantity,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (bytes32 offerHash, Points points)
    {
        address[] memory tokensOffered = new address[](1);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);

        string memory name = "POINTS";
        string memory symbol = "PTS";

        // Create a new Points program
        points = PointsFactory(recipeMarketHub.POINTS_FACTORY()).createPointsProgram(name, symbol, 18, _ipAddress);

        // Allow _ipAddress to mint points in the Points program
        points.addAllowedIP(_ipAddress);

        // Add the Points program to the tokensOffered array
        tokensOffered[0] = address(points);
        incentiveAmountsOffered[0] = 1000e18;

        offerHash = recipeMarketHub.createIPOffer(
            _targetMarketHash, // Referencing the created market
            _quantity, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
    }

    function createIPGdaOffer_WithPoints(
        bytes32 _targetMarketHash,
        uint256 _quantity,
        address _ipAddress
    )
        public
        prankModifier(_ipAddress)
        returns (bytes32 offerHash, Points points)
    {
        address[] memory tokensOffered = new address[](1);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);

        string memory name = "POINTS";
        string memory symbol = "PTS";

        // Create a new Points program
        points = PointsFactory(recipeMarketHub.POINTS_FACTORY()).createPointsProgram(name, symbol, 18, _ipAddress);

        // Allow _ipAddress to mint points in the Points program
        points.addAllowedIP(_ipAddress);

        // Add the Points program to the tokensOffered array
        tokensOffered[0] = address(points);
        incentiveAmountsOffered[0] = 1000e18;

        RecipeMarketHubBase.GDAParams memory gdaParams;
        gdaParams.initialDiscountMultiplier = 10 * 1e18 / 100;
        gdaParams.decayRate = unwrap(div(wrap(SafeCastLib.toInt256(1)), wrap(SafeCastLib.toInt256(2))));
        gdaParams.emissionRate = SafeCastLib.toInt256(1);
        gdaParams.lastAuctionStartTime = 0;

        offerHash = recipeMarketHub.createIPGdaOffer(
            _targetMarketHash, // Referencing the created market
            _quantity, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered, // Incentive amounts offered
            gdaParams
        );
    }

    function calculateIPOfferExpectedIncentiveAndFrontendFee(
        bytes32 offerHash,
        uint256 offerAmount,
        uint256 fillAmount,
        address tokenOffered
    )
        internal
        view
        returns (uint256 fillPercentage, uint256 protocolFeeAmount, uint256 frontendFeeAmount, uint256 incentiveAmount)
    {
        fillPercentage = fillAmount.divWadDown(offerAmount);
        // Fees are taken as a percentage of the promised amounts
        protocolFeeAmount = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, tokenOffered).mulWadDown(fillPercentage);
        frontendFeeAmount = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, tokenOffered).mulWadDown(fillPercentage);
        incentiveAmount = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, tokenOffered).mulWadDown(fillPercentage);
    }

    function calculateIPGdaOfferExpectedIncentiveAndFrontendFee(
        bytes32 offerHash,
        uint256 offerAmount,
        uint256 fillAmount,
        address tokenOffered
    )
        internal
        view
        returns (uint256 fillPercentage, uint256 protocolFeeAmount, uint256 frontendFeeAmount, uint256 incentiveAmount)
    {
        fillPercentage = fillAmount.divWadDown(offerAmount);
        // Fees are taken as a percentage of the promised amounts
        protocolFeeAmount = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, tokenOffered).mulWadDown(fillPercentage);
        frontendFeeAmount = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, tokenOffered).mulWadDown(fillPercentage);
        incentiveAmount = recipeMarketHub.getIncentiveAmountsOfferedForIPGdaOffer(offerHash, tokenOffered, fillAmount).mulWadDown(fillPercentage);
    }

    function calculateAPOfferExpectedIncentiveAndFrontendFee(
        uint256 protocolFee,
        uint256 frontendFee,
        uint256 offerAmount,
        uint256 fillAmount,
        uint256 tokenAmountRequested
    )
        internal
        pure
        returns (uint256 fillPercentage, uint256 frontendFeeAmount, uint256 protocolFeeAmount, uint256 incentiveAmount)
    {
        fillPercentage = fillAmount.divWadDown(offerAmount);
        incentiveAmount = tokenAmountRequested.mulWadDown(fillPercentage);
        protocolFeeAmount = incentiveAmount.mulWadDown(protocolFee);
        frontendFeeAmount = incentiveAmount.mulWadDown(frontendFee);
    }
}
