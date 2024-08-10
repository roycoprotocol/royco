// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract Orderbook {
    struct LPOrder {
        uint256 orderID;
        address lp;
        uint256 market;
        uint256 price;
        uint256 expiry;
        address inputVault;
    }

    struct Market {
        uint256 marketID;
        address inputToken;
        uint256 minimum;
    }

    // Contract State
    uint256 public numOrders;
    mapping(bytes32 => uint256) public orderHashToRemainingQuantity;

    /// @custom:field orderID Set to numOrders - 1 on order creation (zero-indexed)
    /// @custom:field lp The address of the liquidity provider
    /// @custom:field marketID Set to numMarkets - 1 on market creation (zero-indexed)
    /// @custom:field price The desired rewards per input token per second
    /// @custom:field expiry The timestamp after which the order is considered expired
    /// @custom:field inputVault The address of the vault where the input tokens are deposited
    /// @custom:field quantity The amount of input tokens to be deposited
    event LPOrderCreated(
        uint256 indexed orderID,
        address indexed lp,
        uint256 indexed marketID,
        uint256 price,
        uint256 expiry,
        address inputVault,
        uint256 quantity
    );
    /// @custom:field fillAmount The amount of input tokens filled
    event LPOrderFilled(
        uint256 indexed orderID,
        address indexed lp,
        uint256 indexed marketID,
        uint256 price,
        uint256 expiry,
        address inputVault,
        uint256 fillAmountd
    );

    // Errors
    error OrderExpired();
    error NotEnoughRemainingQuantity();
    error MismatchedBaseAsset();
    error OrderDoesNotExist();
    error CannotPlaceExpiredOrder();
    error OrderConditionsNotMet();
    error CannotPlaceZeroQuantityOrder(); //Todo consider replacing with Minimum Ordersize market creation param

    // Modifiers

    // Functions

    constructor() {
        // Initialize contract state
    }

    function createMarket(address baseAsset)
        // minimums?
        public
    {}

    function createLPOrder(uint256 marketID, uint256 price, uint256 expiry, address inputVault, uint256 quantity)
        public
        returns (uint256 orderID)
    {
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOrder();
        }
        if (quantity == 0) {
            revert CannotPlaceZeroQuantityOrder();
        }
        // if (input) ...
    }

    function fillLPOrder(LPOrder memory order, uint256 fillQuantity) public {
        // Check if order is expired
        require(block.timestamp < order.expiry, "Order has expired");

        bytes32 orderHash = getOrderHash(order);

        // Check if order is filled
        require(orderHashToRemainingQuantity[orderHash] > 0, "Order is already filled");

        //withdraw from base pool

        //deposit into new pool

        // Emit trade event
        // emit Trade();
    }

    function getOrderFillAmount(LPOrder memory order) public view returns (uint256) {
        // TLOAD HERE return orderHashToRemainingQuantity[getOrderHash(order)];
    }

    function getOrderHash(LPOrder memory order) public pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }
}
