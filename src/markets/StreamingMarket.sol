// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Market, MarketType} from "./interfaces/Market.sol";

contract StreamingMarket is Market {
    function getMarketType() external pure override returns (MarketType) {
        return MarketType.STREAMING;
    }
}
