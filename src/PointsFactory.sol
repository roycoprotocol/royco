// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Points } from "src/Points.sol";
import { RecipeOrderbook } from "src/RecipeOrderbook.sol";
import { Ownable2Step, Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";


/// @title PointsFactory
/// @author CopyPaste, corddry, ShivaanshK
/// @dev A simple program for creating points programs
contract PointsFactory is Ownable2Step {
    /// @notice Mapping of Points Program address => bool (indicator of if Points Program was deployed using this factory)
    mapping(address => bool) public isPointsProgram;

    /// @notice Mapping of Orderbook address => bool (indicator of if the address is of a Royco orderbook)
    mapping(address => bool) public isRecipeOrderbook;

    /// @notice Emitted when creating a points program using this factory
    event NewPointsProgram(Points indexed points, string indexed name, string indexed symbol);

    /// @notice Emitted when adding an orderbook to this Points Factory
    event RecipeOrderbookAdded(address indexed recipeOrderbook);

    /// @param _owner The owner of the points factory - responsible for adding valid orderbooks to the 
    constructor(address _owner) Ownable(_owner) {}

    /// @param _recipeOrderbook The orderbook to add to the Points Factory
    function addRecipeOrderbook(address _recipeOrderbook) external onlyOwner {
        isRecipeOrderbook[_recipeOrderbook] = true;
        emit RecipeOrderbookAdded(_recipeOrderbook);
    }

    /// @param _name The name for the new points program
    /// @param _symbol The symbol for the new points program
    /// @param _decimals The amount of decimals per point
    /// @param _owner The owner of the new points program
    function createPointsProgram(
        string memory _name,
        string memory _symbol,
        uint256 _decimals,
        address _owner
    )
        external
        returns (Points points)
    {
        bytes32 salt = keccak256(abi.encodePacked(_name, _symbol, _decimals, _owner));
        points = new Points{salt: salt}(_name, _symbol, _decimals, _owner);
        isPointsProgram[address(points)] = true;

        emit NewPointsProgram(points, _name, _symbol);
    }
}
