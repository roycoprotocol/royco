// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Market, MarketType} from "./interfaces/Market.sol";
import {OrderFactory} from "./interfaces/OrderFactory.sol";

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

contract LumpSumMarket is Market, OrderFactory {
    /*//////////////////////////////////////////////////////////////
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    /// @notice Array of tokens utilized as rewards in the market.
    ERC20[] public tokens;

    /// @notice Array of weiroll commands representing the market action.
    bytes32[] public weirollCommands;

    /// @notice Returns the market type
    MarketType public constant override getMarketType = MarketType.LUMP_SUM;

    /// @notice Initializes the contract.
    /// @param _orderImplementation Address of the order implementation contract.
    /// @param _tokens Array of tokens utilized as rewards in the market.
    /// @param _weirollCommands Array of weiroll commands representing the market action.
    function initialize(
        address _orderImplementation,
        ERC20[] calldata _tokens,
        bytes32[] calldata _weirollCommands
    ) external {
        tokens = _tokens;
        weirollCommands = _weirollCommands;
        orderImplementation = _orderImplementation;
    }
}
