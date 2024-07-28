// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// MarketFactory and Market Contracts
import {MarketFactory} from "../src/MarketFactory.sol";
import {StreamingMarket} from "../src/markets/StreamingMarket.sol";
import {MarketType} from "../src/markets/interfaces/Market.sol";

// Testing contracts
import {DSTestPlus} from "../lib/solmate/src/test/utils/DSTestPlus.sol";

/// @title MarketFactoryTest
/// @author Royco
/// @notice Tests for the MarketFactory contract
contract LumpSumMarketTest is DSTestPlus {
    // Implementation addresses
    address public marketImplementation;
    MarketFactory public marketFactory;

    // Streaming contract
    StreamingMarket public streamingMarket;

    function setUp() public {
        // Deploy market implementations
        marketImplementation = address(new StreamingMarket());

        // Deploy MarketFactory
        // The streaming market implementation address is not needed for this test so we pass the same address twice.
        marketFactory = new MarketFactory(marketImplementation, marketImplementation);

        // Deploy two lump sum markets. The first one will be used to increase the market ID.
        streamingMarket = StreamingMarket(marketFactory.deployStreamingMarket());
    }

    function testMarketId() public {
        // Market ID should be 0
        assertEq(streamingMarket.getMarketId(), 0);
    }

    function testMarketType() public {
        // Market type should be Streaming
        assertEq(uint256(streamingMarket.getMarketType()), uint256(MarketType.STREAMING));
    }
}
