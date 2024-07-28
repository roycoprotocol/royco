// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Clone} from "../../lib/clones-with-immutable-args/src/Clone.sol";

enum MarketType {
    LUMP_SUM,
    STREAMING
}

abstract contract IMarket is Clone {
    function getMarketId() external pure returns (uint256) {
        return _getArgUint256(0);
    }

    function getMarketType() external view virtual returns (MarketType);
}
