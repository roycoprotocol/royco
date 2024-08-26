// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC4626i } from "src/ERC4626i.sol";
import { RecipeOrderbook } from "src/RecipeOrderbook.sol";

import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

/// @title Points
/// @author CopyPaste, corddry
/// @dev A simple program for running points programs
contract Points is Owned(msg.sender) {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _name The name of the points program
    /// @param _symbol The symbol for the points program
    /// @param _decimals The amount of decimals per 1 point
    /// @param _allowedVault The vault allowed to mint and use these points
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _decimals,
        ERC4626i _allowedVault,
        RecipeOrderbook _orderbook
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        allowedVault = _allowedVault;
        orderbook = _orderbook;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Award(address indexed to, uint256 indexed amount, uint256 indexed campaignId);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @dev The allowed vault to call this contract
    ERC4626i public immutable allowedVault;
    /// @dev The RecipeOrderbook for IP Orders
    RecipeOrderbook public immutable orderbook;

    /// @dev The name of the points program
    string public name;
    /// @dev The symbol for the points program
    string public symbol;
    /// @dev We track all points logic using base 1
    uint256 public decimals;
    /// @dev Track which campaignIds are allowed to mint
    mapping(uint256 campaignId => bool allowed) public allowedCampaigns;

    /*//////////////////////////////////////////////////////////////
                              POINTS AUTH
    //////////////////////////////////////////////////////////////*/
    /// @param start The start date of the campaign
    /// @param end The end date of the campaign
    /// @param totalRewards The total amount of points to distribute
    function createPointsRewardsCampaign(uint256 start, uint256 end, uint256 totalRewards) external onlyOwner {
        uint256 campaignId = allowedVault.totalCampaigns() + 1;
        allowedCampaigns[campaignId] = true;

        uint256 newCampaign = allowedVault.createRewardsCampaign(ERC20(address(this)), start, end, totalRewards);

        /// Safe check for redundancy
        require(newCampaign == campaignId);
    }

    function createIPOrderWithPoints() external onlyOwner {}

    error CampaignNotAuthorized();
    error OnlyIncentivizedVault();

    /// @param campaignId The campaignId being supplied
    modifier onlyAllowedCampaigns(uint256 campaignId) {
        if (msg.sender != address(allowedVault)) {
            revert OnlyIncentivizedVault();
        }

        if (!allowedCampaigns[campaignId]) {
            revert CampaignNotAuthorized();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 POINTS
    //////////////////////////////////////////////////////////////*/

    /// @param to The address to mint points to
    /// @param campaignId The campaignId to mint points for
    function award(address to, uint256 amount, uint256 campaignId) external onlyAllowedCampaigns(campaignId) {
        emit Award(to, amount, campaignId);
    }
}
