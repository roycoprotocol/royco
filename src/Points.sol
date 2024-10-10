// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { PointsFactory } from "src/PointsFactory.sol";
import { Ownable2Step, Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @title Points
/// @author CopyPaste, corddry, ShivaanshK
/// @dev A simple contract for running Points Programs
contract Points is Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _name The name of the points program
    /// @param _symbol The symbol for the points program
    /// @param _decimals The amount of decimals to use for accounting with points
    /// @param _owner The owner of the points program
    constructor(string memory _name, string memory _symbol, uint256 _decimals, address _owner) Ownable(_owner) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        // Enforces that the Points Program deployer is a factory
        pointsFactory = PointsFactory(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Award(address indexed to, uint256 indexed amount);
    event AllowedVaultAdded(address indexed vault);
    event VaultRemoved(address indexed vault);
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @dev Maps a vault to if the vault is allowed to call this contract
    mapping(address => bool) public isAllowedVault;

    /// @dev The PointsFactory used to create this program
    PointsFactory public immutable pointsFactory;

    /// @dev The name of the points program
    string public name;
    /// @dev The symbol for the points program
    string public symbol;
    /// @dev We track all points logic using base 1
    uint256 public decimals;
    /// @dev Track which RecipeKernel IPs are allowed to mint
    mapping(address => bool) public allowedIPs;

    /*//////////////////////////////////////////////////////////////
                              POINTS AUTH
    //////////////////////////////////////////////////////////////*/
    error VaultIsDuplicate();

    /// @param vault The address to add to the allowed vaults for the points program
    function addAllowedVault(address vault) external onlyOwner {
        if (isAllowedVault[vault]) {
            revert VaultIsDuplicate();
        }

        isAllowedVault[vault] = true;

        emit AllowedVaultAdded(vault);
    }

    /// @param ip The incentive provider address to allow to mint points on RecipeKernel
    function addAllowedIP(address ip) external onlyOwner {
        allowedIPs[ip] = true;
    }

    error OnlyAllowedVaults();
    error OnlyRecipeKernel();
    error NotAllowedIP();

    modifier onlyAllowedVaults() {
        if (!isAllowedVault[msg.sender]) {
            revert OnlyAllowedVaults();
        }
        _;
    }

    /// @dev only the RecipeKernel can call this function
    /// @param ip The address to check if allowed
    modifier onlyRecipeKernelAllowedIP(address ip) {
        if (!pointsFactory.isRecipeKernel(msg.sender)) {
            revert OnlyRecipeKernel();
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
    function award(address to, uint256 amount, address ip) external onlyRecipeKernelAllowedIP(ip) {
        emit Award(to, amount);
    }
}
