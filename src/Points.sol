// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC4626i } from "src/ERC4626i.sol";
import { RecipeOrderbook } from "src/RecipeOrderbook.sol";

import { Ownable } from "lib/solady/src/auth/Ownable.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

/// @title Points
/// @author CopyPaste, corddry
/// @dev A simple program for running points programs
contract Points is Ownable {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _name The name of the points program
    /// @param _symbol The symbol for the points program
    /// @param _decimals The amount of decimals per 1 point
    constructor(string memory _name, string memory _symbol, uint256 _decimals, address _owner, RecipeOrderbook _orderbook) {
        _initializeOwner(_owner);

        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        orderbook = _orderbook;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Award(address indexed to, uint256 indexed amount);
    event AllowedVaultAdded(address indexed vault);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @dev The allowed vaults to call this contract
    address[] public allowedVaults;
    /// @dev Maps a vault to if the vault is allowed to call this contract
    mapping(address => bool) public isAllowedVault;

    /// @dev The RecipeOrderbook for IP Orders
    RecipeOrderbook public immutable orderbook;

    /// @dev The name of the points program
    string public name;
    /// @dev The symbol for the points program
    string public symbol;
    /// @dev We track all points logic using base 1
    uint256 public decimals;
    /// @dev Track which RecipeOrderbook IPs are allowed to mint
    mapping(address => bool) public allowedIPs;

    /*//////////////////////////////////////////////////////////////
                              POINTS AUTH
    //////////////////////////////////////////////////////////////*/

    function addAllowedVault(address vault) external onlyOwner {
        allowedVaults.push(vault);
        isAllowedVault[vault] = true;
        emit AllowedVaultAdded(vault);
    }

    /// @param ip The incentive provider address to allow to mint points on RecipeOrderbook
    function addAllowedIP(address ip) external onlyOwner {
        allowedIPs[ip] = true;
    }

    /// @param ip The incentive provider address to disallow to mint points on RecipeOrderbook
    function removeAllowedIP(address ip) external onlyOwner {
        allowedIPs[ip] = false;
    }

    error OnlyAllowedVaults();
    error OnlyRecipeOrderbook();
    error NotAllowedIP();

    modifier onlyAllowedVaults {
        if (!isAllowedVault[msg.sender]) {
            revert OnlyAllowedVaults();
        }
        _;
    }

    /// @dev only the orderbook can call this function
    /// @param ip The address to check if allowed
    modifier onlyRecipeOrderbookAllowedIP(address ip) {
        if (msg.sender != address(orderbook)) {
            revert OnlyRecipeOrderbook();
        }
        if (!allowedIPs[ip]) {
            revert NotAllowedIP();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 POINTS
    //////////////////////////////////////////////////////////////*/

    /// @param to The address to mint points to
    /// @param amount  The amount of points to award to the `to` address
    function award(address to, uint256 amount) external onlyAllowedVaults {
        emit Award(to, amount);
    }

    /// @param to The address to mint points to
    /// @param amount  The amount of points to award to the `to` address
    /// @param ip The incentive provider attempting to mint the points
    function award(address to, uint256 amount, address ip) external onlyRecipeOrderbookAllowedIP(ip) {
        emit Award(to, amount);
    }
}
