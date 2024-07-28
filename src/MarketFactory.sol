// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ClonesWithImmutableArgs} from "../lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";

/// @title Market Factory
/// @author Royco
/// @notice Factory for creating new markets
/// @dev This contract is responsible for creating new markets and setting up the initial state of the market.
contract MarketFactory {
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    using ClonesWithImmutableArgs for address;
}
