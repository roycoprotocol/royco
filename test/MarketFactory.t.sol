// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// MarketFactory and Market Contracts
import {MarketFactory} from "../src/MarketFactory.sol";
import {StreamingMarket} from "../src/markets/StreamingMarket.sol";
import {LumpSumMarket} from "../src/markets/LumpSumMarket.sol";
import {MarketType} from "../src/markets/interfaces/Market.sol";

// Testing contracts
import {DSTestPlus} from "../lib/solmate/src/test/utils/DSTestPlus.sol";
import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";

/// @title MarketFactoryTest
/// @author Royco
/// @notice Tests for the MarketFactory contract
contract MarketFactoryTest is DSTestPlus {
    // Implementation addresses
    address public lumpSumMarketImplementation;
    address public streamingMarketImplementation;
    MarketFactory public marketFactory;

    function setUp() public {
        // Deploy market implementations
        lumpSumMarketImplementation = address(new LumpSumMarket());
        streamingMarketImplementation = address(new StreamingMarket());

        // Deploy MarketFactory
        // Order implementation address is not needed for this test so we pass the zero address.
        marketFactory = new MarketFactory(lumpSumMarketImplementation, streamingMarketImplementation, address(0));
    }

    function testStreamingMarketCreation() public {
        // Deploy a streaming market
        StreamingMarket streamingMarket = StreamingMarket(marketFactory.deployStreamingMarket());

        // Market ID should be 0
        assertEq(streamingMarket.getMarketId(), 0);
    }

    function testLumpSumMarketCreation() public {
        // Deploy a lump sum market
        LumpSumMarket lumpSumMarket = LumpSumMarket(
            marketFactory.deployLumpSumMarket(new ERC20[](0), new bytes32[](0))
        );

        // Market ID should be 0
        assertEq(lumpSumMarket.getMarketId(), 0);
    }

    function testMarketIdIncrement() public {
        // Deploy two markets
        StreamingMarket streamingMarket = StreamingMarket(marketFactory.deployStreamingMarket());
        LumpSumMarket lumpSumMarket = LumpSumMarket(
            marketFactory.deployLumpSumMarket(new ERC20[](0), new bytes32[](0))
        );

        // Market IDs should be incremented
        assertEq(streamingMarket.getMarketId(), 0);
        assertEq(lumpSumMarket.getMarketId(), 1);
    }
}
