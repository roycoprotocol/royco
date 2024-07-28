// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ClonesWithImmutableArgs} from "../lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";

import {MarketType} from "./interfaces/IMarket.sol";

/// @title Market Factory
/// @author Royco
/// @notice Factory for creating new markets
/// @dev This contract is responsible for creating new markets and setting up the initial state of the market.
contract MarketFactory {
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    using ClonesWithImmutableArgs for address;

    /// @dev The address of the LumpSumMarket implementation contract
    address public immutable LUMP_SUM_IMPLEMENTATION;

    /// @dev The address of the StreamingMarket implementation contract
    address public immutable STREAMING_IMPLEMENTATION;

    constructor(address lumpSumImplementation_, address streamingImplementation_) {
        LUMP_SUM_IMPLEMENTATION = lumpSumImplementation_;
        STREAMING_IMPLEMENTATION = streamingImplementation_;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev The current market id
    uint256 public marketId;

    /// @dev Event emitted when a new market is deployed.
    // todo: which values need to be indexed?
    event MarketDeployed(MarketType indexed marketType, address indexed marketAddress, uint256 indexed marketId);

    /// @dev Deploy a new LumpSumMarket
    function deployLumpSumMarket() external returns (address clone) {
        // Encode the marketId to be stored within the clone bytecode.
        bytes memory data = abi.encodePacked(marketId);
        clone = LUMP_SUM_IMPLEMENTATION.clone(data);

        // Increment the marketID.
        marketId++;

        // Emit the event.
        emit MarketDeployed(MarketType.LUMP_SUM, clone, marketId);
    }

    /// @dev Deploy a new StreamingMarket
    function deployStreamingMarket() external returns (address clone) {
        // Encode the marketId to be stored within the clone bytecode.
        bytes memory data = abi.encodePacked(marketId);
        clone = STREAMING_IMPLEMENTATION.clone(data);

        // Increment the marketID.
        marketId++;

        // Emit the event.
        emit MarketDeployed(MarketType.STREAMING, clone, marketId);
    }
}
