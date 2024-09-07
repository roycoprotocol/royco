// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Points } from "src/Points.sol";

import { ERC4626i } from "src/ERC4626i.sol";
import { RecipeOrderbook } from "src/RecipeOrderbook.sol";

/// @title PointsFactory
/// @author CopyPaste, corddry, ShivaanshK
/// @dev A simple program for creating points programs
contract PointsFactory {
    mapping(address => bool) public isPointsProgram;

    event NewPointsProgram(Points indexed points, string name, string symbol, address allowedVault, address orderbook);

    /// @param _name The name for the new points program
    /// @param _symbol The symbol for the new points program
    /// @param _decimals The amount of decimals for 1 Point
    /// @param _allowedVault The ERC4626i Incentivized Vault
    /// @param _orderbook The RecipeOrderbook for Weiroll Rewards Programs
    function createPointsProgram(
        string memory _name,
        string memory _symbol,
        uint256 _decimals,
        address _owner,
        ERC4626i _allowedVault,
        RecipeOrderbook _orderbook
    )
        external
        returns (Points points)
    {
        points = new Points(_name, _symbol, _decimals, _owner, _allowedVault, _orderbook);
        isPointsProgram[address(points)] = true;

        emit NewPointsProgram(points, _name, _symbol, address(_allowedVault), address(_orderbook));
    }
}
