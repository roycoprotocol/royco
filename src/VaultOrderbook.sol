// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {ERC4626} from "../lib/solmate/src/tokens/ERC4626.sol";
import {ERC4626i} from "src/ERC4626i.sol";

contract VaultOrderbook {
    struct LPOrder {
        uint256 orderID;
        address targetVault; //TODO convert to 4626i
        address lp;
        address fundingVault;
        uint256 expiry;
        address[] tokens;
        uint256[] prices;
    }

    // Contract State
    uint256 public numOrders;
    // uint256 public protocolFee; // 1e18 == 100% fee //TODO: set these aside when adding rewards to 4626i
    // uint256 public minimumFrontendFee; // 1e18 == 100% fee

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
        address indexed targetVault,
        address indexed lp,
        address fundingVault,
        uint256 expiry,
        address[] tokensRequested,
        uint256[] tokenRatesRequested,
        uint256 quantity
    );

    event LPOrderCancelled(uint256 indexed orderID);

    event LPOrderFilled(uint256 indexed orderID, address indexed targetVault, address indexed lp, uint256 quantity);

    // TODO claim fees event

    // Errors
    error OrderExpired();
    error NotEnoughRemainingQuantity();
    error MismatchedBaseAsset();
    error OrderDoesNotExist();
    error MarketDoesNotExist();
    error CannotPlaceExpiredOrder();
    error OrderConditionsNotMet();
    error CannotPlaceZeroQuantityOrder(); //Todo consider replacing with Minimum Ordersize market creation param
    error NotEnoughBaseAssetInVault();
    error InsufficientApproval();
    error ArrayLengthMismatch();

    // Modifiers

    // Functions

    /// @dev Setting an expiry of 0 means the order never expires
    function createLPOrder(
        address targetVault,
        address fundingVault,
        uint256 quantity,
        uint256 expiry,
        address[] memory tokens,
        uint256[] memory prices
    ) public returns (uint256) {
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOrder();
        }
        if (quantity == 0) {
            revert CannotPlaceZeroQuantityOrder();
        }
        if (tokens.length != prices.length) {
            revert ArrayLengthMismatch();
        }
        if (quantity > ERC4626(fundingVault).maxWithdraw(msg.sender)) {
            revert NotEnoughBaseAssetInVault();
        }
        if (ERC4626(fundingVault).allowance(msg.sender, address(this)) < quantity) {
            revert InsufficientApproval();
        }
        if (ERC4626(targetVault).asset() != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }

        LPOrder memory order = LPOrder(numOrders, targetVault, msg.sender, fundingVault, expiry, tokens, prices);
        orderHashToRemainingQuantity[getOrderHash(order)] = quantity;
        return (numOrders++);
    }

    function allocateOrder(LPOrder memory order) public {
        //TODO: partial fills
        if (order.expiry != 0 && block.timestamp >= order.expiry) {
            revert OrderExpired();
        }

        bytes32 orderHash = getOrderHash(order);
        uint256 remainingQuantity = orderHashToRemainingQuantity[orderHash];

        if (remainingQuantity == 0) {
            revert NotEnoughRemainingQuantity();
        }

        uint256 len = order.tokens.length;
        for (uint256 i = 0; i < len; ++i) {
            // if (ERC4626i(order.targetVault).previewRewards(order.tokens[i]) < order.prices[i]) { //TODO: connect with 4626i preview function
            //     //TODO: update with 4626i preview function signature, post-deposit rates
            //     revert OrderConditionsNotMet();
            // }
        }

        // If no revert yet, the order is within its conditions

        // Withdraw from the funding vault
        ERC4626(order.fundingVault).withdraw(remainingQuantity, address(this), order.lp);

        // Deposit into the target vault
        ERC4626i(order.targetVault).deposit(remainingQuantity, order.lp); //TODO: update with 4626i deposit function signature

        orderHashToRemainingQuantity[orderHash] = 0;

        emit LPOrderFilled(order.orderID, order.targetVault, order.lp, remainingQuantity);
    }

    function allocateOrders(LPOrder[] memory orders) public {
        uint256 len = orders.length;
        for (uint256 i = 0; i < len; ++i) {
            allocateOrder(orders[i]);
        }
    }

    function getOrderHash(LPOrder memory order) public pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }
}
