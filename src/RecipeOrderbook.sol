// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {ERC4626} from "../lib/solmate/src/tokens/ERC4626.sol";

contract VaultOrderbook {

    struct LPOrder {
        uint256 orderID;
        uint256 targetRecipeID;
        address lp;
        address fundingVault;
        uint256 expiry;
        address[] tokens;
        uint256[] prices;
    }

    struct IPOrder {
        uint256 targetRecipeID;
        uint256 expiry;
        address[] tokensOffered;
        mapping(address => uint256) tokenAmountsOffered;
    }

    struct Recipe {
        bytes32[] weirollCommands;
        bytes[] weirollState;
    }

    struct WeirollMarket {
        ERC20 inputToken;
        Recipe depositRecipe;
        Recipe withdrawRecipe;
    }

    // Contract State
    
    uint256 public numOrders;
    uint256 public numMarkets;

    uint256 public protocolFee; // 1e18 == 100% fee
    uint256 public minimumFrontendFee; // 1e18 == 100% fee

    mapping(uint256 => WeirollMarket) public marketIDToWeirollMarket;
    mapping(uint256 => IPOrder) public orderIDToIPOrder;
    mapping(bytes32 => uint256) public orderHashToRemainingQuantity;

    /// @custom:field orderID Set to numOrders - 1 on order creation (zero-indexed)
    /// @custom:field targetVault The address of the vault where the input tokens will be deposited
    /// @custom:field lp The address of the liquidity provider
    /// @custom:field fundingVault The address of the vault where the input tokens are currently deposited
    /// @custom:field expiry The timestamp after which the order is considered expired
    /// @custom:field price The desired rewards per input token (per second if a Vault market)
    /// @custom:field quantity The amount of input tokens to be deposited
    event LPOrderCreated(
        uint256 indexed orderID,
        uint256 indexed targetMarketID,
        address indexed lp,
        address fundingVault,
        uint256 expiry,
        address[] tokensRequested,
        uint256[] tokenAmountsRequested,
        uint256 quantity
    );

    event IPOrderCreated(
        uint256 indexed IPOrderID,
    )

    event LPOrderFilled(
        uint256 indexed orderID,
        uint256 indexed targetMarketID,
        address indexed lp,
        uint256 quantity
    );

    // Errors //TODO clean up
    error OrderExpired();
    error NotEnoughRemainingQuantity();
    error MismatchedBaseAsset();
    error OrderDoesNotExist();
    error MarketDoesNotExist();
    error CannotPlaceExpiredOrder();
    error OrderConditionsNotMet();
    error CannotPlaceZeroQuantityOrder();
    error NotEnoughBaseAssetInVault();
    error InsufficientApproval();
    error ArrayLengthMismatch();

    /// @dev Setting an expiry of 0 means the order never expires
    function createLPOrder(uint256 targetMarketID, address fundingVault, uint256 quantity, uint256 expiry, address[] memory tokensRequested, uint256[] memory tokenAmountsRequested) public returns (uint256) {
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOrder();
        }
        if (quantity == 0) {
            revert CannotPlaceZeroQuantityOrder();
        }
        if (tokensRequested.length != tokenAmountsRequested.length) {
            revert ArrayLengthMismatch();
        }
        if (quantity > ERC4626(fundingVault).maxWithdraw(msg.sender)) {
            revert NotEnoughBaseAssetInVault();
        }
        if (ERC4626(fundingVault).allowance(msg.sender, address(this)) < quantity) {
            revert InsufficientApproval();
        }
        if (marketIDToWeirollMarket[targetMarketID].inputToken != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }

        LPOrder memory order = LPOrder(numOrders, targetMarketID, msg.sender, fundingVault, expiry, tokensRequested, tokenAmountsRequested);
        orderHashToRemainingQuantity[getOrderHash(order)] = quantity;
        return(numOrders++);
    }

    // @dev IP must approve all tokens to be spent by the orderbook before calling this function
    function createIPOrder(uint256 targetMarketID, uint256 expiry, address[] memory tokens, uint256[] memory amounts) public returns (uint256) {
        if (targetMarketID >= numMarkets) {
            revert MarketDoesNotExist();
        }
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOrder();
        }
        if (tokens.length != amounts.length) {
            revert ArrayLengthMismatch();
        }

        IPOrder storage order = orderIDToIPOrder[numOrders];

        order.targetMarketID = targetMarketID;
        order.expiry = expiry;
        order.tokensOffered = tokens;
        for (uint256 i = 0; i < tokens.length; ++i) {
            order.tokenAmountsOffered[tokens[i]] = amounts[i];
            ERC20(tokens[i]).transferFrom(msg.sender, address(this), amounts[i]);
            //TODO take fees
        }

        IPOrder memory order = IPOrder(targetMarketID, expiry, tokens, amounts);
        
        return(numOrders++);
    }

    function fillIPOrder(uint256 orderID) public {
        IPOrder storage order = orderIDToIPOrder[orderID];
        if (order.expiry != 0 && block.timestamp >= order.expiry) {
            revert OrderExpired();
        }

        WeirollMarket storage market = marketIDToWeirollMarket[order.targetMarketID];

        WeirollWallet

        delete orderIDToIPOrder[orderID];
    }

    function fillLPOrder(uint256 orderID) public {
        //TODO
    }


    function getOrderHash(LPOrder memory order) public pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }
}
