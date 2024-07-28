// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMarket, MarketType} from "./interfaces/IMarket.sol";

contract LumpSumMarket is IMarket {
    function getMarketType() external pure override returns (MarketType) {
        return MarketType.LUMP_SUM;
    }
}
