// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// MarketFactory and Market Contracts
import {MarketFactory} from "../src/MarketFactory.sol";
import {StreamingMarket} from "../src/markets/StreamingMarket.sol";
import {LumpSumMarket} from "../src/markets/LumpSumMarket.sol";
import {MarketType} from "../src/markets/interfaces/Market.sol";

// Testing contracts
import {DSTestPlus} from "../lib/solmate/src/test/utils/DSTestPlus.sol";

/// @title MarketFactoryTest
/// @author Royco
/// @notice Tests for the MarketFactory contract
contract MarketFactoryTest is DSTestPlus {
    // Implementation addresses
    address public streamingMarketImplementation;
    address public lumpSumMarketImplementation;
    MarketFactory public marketFactory;

    function setUp() public {
        // Deploy market implementations
        streamingMarketImplementation = address(new StreamingMarket());
        lumpSumMarketImplementation = address(new LumpSumMarket());

        // Deploy MarketFactory
        // Order implementation address is not needed for this test so we pass the zero address.
        marketFactory = new MarketFactory(streamingMarketImplementation, lumpSumMarketImplementation, address(0));
    }

    function testStreamingMarketCreation() public {
        // Deploy a streaming market
        StreamingMarket streamingMarket = StreamingMarket(marketFactory.deployStreamingMarket());

        // Market ID should be 0
        assertEq(streamingMarket.getMarketId(), 0);
    }

    function testLumpSumMarketCreation() public {
        // Deploy a lump sum market
        LumpSumMarket lumpSumMarket = LumpSumMarket(marketFactory.deployLumpSumMarket());

        // Market ID should be 0
        assertEq(lumpSumMarket.getMarketId(), 0);
    }

    function testMarketIdIncrement() public {
        // Deploy two markets
        StreamingMarket streamingMarket = StreamingMarket(marketFactory.deployStreamingMarket());
        LumpSumMarket lumpSumMarket = LumpSumMarket(marketFactory.deployLumpSumMarket());

        // Market IDs should be incremented
        assertEq(streamingMarket.getMarketId(), 0);
        assertEq(lumpSumMarket.getMarketId(), 1);
    }
}
