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
    // Contract deployments
    WeirollWallet public weirollImplementation;
    RecipeOrderbook public orderbook;
    MockERC20 public mockLiquidityToken;
    MockERC20 public mockIncentiveToken;
    MockERC4626 public mockVault;
    PointsFactory public pointsFactory;

    // Fees set in orderbook constructor
    uint256 initialProtocolFee;
    uint256 initialMinimumFrontendFee;

    function setUpRecipeOrderbookTests(uint256 _initialProtocolFee, uint256 _initialMinimumFrontendFee) public {
        setupBaseEnvironment();

        weirollImplementation = new WeirollWallet();
        mockLiquidityToken = new MockERC20("Mock Liquidity Token", "MLT");
        mockIncentiveToken = new MockERC20("Mock Incentive Token", "MIT");
        mockVault = new MockERC4626(mockLiquidityToken);
        pointsFactory = new PointsFactory();

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
}
