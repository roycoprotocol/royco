// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// MarketFactory and Market Contracts
import {MarketFactory} from "../src/MarketFactory.sol";
import {LumpSumMarket} from "../src/markets/LumpSumMarket.sol";
import {MarketType} from "../src/markets/interfaces/Market.sol";
import {Order} from "../src/Order.sol";

// Testing contracts
import {DSTestPlus} from "../lib/solmate/src/test/utils/DSTestPlus.sol";

/// @title MarketFactoryTest
/// @author Royco
/// @notice Tests for the MarketFactory contract
contract LumpSumMarketTest is DSTestPlus {
    // Implementation addresses
    address public marketImplementation;
    MarketFactory public marketFactory;

    // LumpSumMarket contract
    LumpSumMarket public lumpSumMarket;

    function setUp() public {
        // Deploy market implementations
        marketImplementation = address(new LumpSumMarket());

        // Deploy MarketFactory
        // The streaming market implementation address is not needed for this test so we pass the same address twice.
        marketFactory = new MarketFactory(marketImplementation, marketImplementation, address(new Order()));

        // Deploy two lump sum markets. The first one will be used to increase the market ID.
        lumpSumMarket = LumpSumMarket(marketFactory.deployLumpSumMarket());
    }

    function testMarketId() public {
        // Market ID should be 0
        assertEq(lumpSumMarket.getMarketId(), 0);
    }

    function testMarketType() public {
        // Market type should be Streaming
        assertEq(uint256(lumpSumMarket.getMarketType()), uint256(MarketType.LUMP_SUM));
    }
}
