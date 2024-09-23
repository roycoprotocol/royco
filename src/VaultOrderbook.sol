// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC20 } from "../lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "../lib/solmate/src/tokens/ERC4626.sol";
import { ERC4626i } from "src/ERC4626i.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { Ownable2Step, Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @title VaultOrderbook
/// @author CopyPaste, corddry, ShivaanshK
/// @notice Orderbook Contract for Incentivizing AP/IPs to participate incentivized ERC4626 markets
contract VaultOrderbook is Ownable2Step {
    using SafeTransferLib for ERC20;

    /// @custom:field orderID Set to numOrders - 1 on order creation (zero-indexed)
    /// @custom:field targetVault The address of the vault where the input tokens will be deposited
    /// @custom:field ap The address of the liquidity provider
    /// @custom:field fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @custom:field expiry The timestamp after which the order is considered expired
    /// @custom:field tokensRequested The incentive tokens requested by the AP in order to fill the order
    /// @custom:field tokenRatesRequested The desired rewards per input token per second to fill the order, measured in
            /// wei of rewards token per wei of deposited assets per second, scaled up by 1e18 to avoid precision loss
    struct APOrder {
        uint256 orderID;
        address targetVault;
        address ap;
        address fundingVault;
        uint256 expiry;
        address[] tokensRequested;
        uint256[] tokenRatesRequested;
    }

    /// @notice starts at 0 and increments by 1 for each order created
    uint256 public numOrders;

    /// @notice maps order hashes to the remaining quantity of the order
    mapping(bytes32 => uint256) public orderHashToRemainingQuantity;

    /// @param orderID Set to numOrders - 1 on order creation (zero-indexed)
    /// @param targetVault The address of the vault where the input tokens will be deposited
    /// @param ap The address of the liquidity provider
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @param expiry The timestamp after which the order is considered expired
    /// @param tokensRequested The incentive tokens requested by the AP in order to fill the order
    /// @param tokenRatesRequested The desired rewards per input token per second to fill the order
    /// @param quantity The total amount of the base asset to be withdrawn from the funding vault
    event APOrderCreated(
        uint256 indexed orderID,
        address indexed targetVault,
        address indexed ap,
        address fundingVault,
        uint256 expiry,
        address[] tokensRequested,
        uint256[] tokenRatesRequested,
        uint256 quantity
    );

    /// @notice emitted when an order is cancelled and the remaining quantity is set to 0
    event APOrderCancelled(uint256 indexed orderID);

    /// @notice emitted when an AP is allocated to a vault
    event APOrderFilled(uint256 indexed orderID, uint256 quantity);

    /// @notice emitted when trying to fill an order that has expired
    error OrderExpired();
    /// @notice emitted when trying to fill an order with more input tokens than the remaining order quantity
    error NotEnoughRemainingQuantity();
    /// @notice emitted when the base asset of the target vault and the funding vault do not match
    error MismatchedBaseAsset();
    /// @notice emitted when trying to fill a non-existent order (remaining quantity of 0)
    error OrderDoesNotExist();
    /// @notice emitted when trying to create an order with an expiry in the past
    error CannotPlaceExpiredOrder();
    /// @notice emitted when trying to allocate an AP, but the AP's requested tokens are not met
    error OrderConditionsNotMet();
    /// @notice emitted when trying to create an order with a quantity of 0
    error CannotPlaceZeroQuantityOrder();
    /// @notice emitted when the AP does not have sufficient assets in the funding vault, or in their wallet to place an AP order
    error NotEnoughBaseAssetToOrder();
    /// @notice emitted when the AP does not have sufficient assets in the funding vault, or in their wallet to allocate an order
    error NotEnoughBaseAssetToAllocate();
    /// @notice emitted when the length of the tokens and prices arrays do not match
    error ArrayLengthMismatch();
    /// @notice emitted when the AP tries to cancel an order that they did not create
    error NotOrderCreator();

    constructor() Ownable(msg.sender) { }

    /// @dev Setting an expiry of 0 means the order never expires
    /// @param targetVault The address of the vault where the liquidity will be deposited
    /// @param fundingVault The address of the vault where the liquidity will be withdrawn from, if set to 0, the AP will deposit the base asset directly
    /// @param quantity The total amount of the base asset to be withdrawn from the funding vault
    /// @param expiry The timestamp after which the order is considered expired
    /// @param tokensRequested The incentive tokens requested by the AP in order to fill the order
    /// @param tokenRatesRequested The desired rewards per input token per second to fill the order
    function createAPOrder(
        address targetVault,
        address fundingVault,
        uint256 quantity,
        uint256 expiry,
        address[] memory tokensRequested,
        uint256[] memory tokenRatesRequested
    )
        public
        returns (uint256)
    {
        // Check order isn't expired (expiries of 0 live forever)
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOrder();
        }
        // Check order isn't empty
        if (quantity == 0) {
            revert CannotPlaceZeroQuantityOrder();
        }
        // Check token and price arrays are the same length
        if (tokensRequested.length != tokenRatesRequested.length) {
            revert ArrayLengthMismatch();
        }
        // Check assets match in-kind
        // NOTE: The cool use of short-circuit means this call can't revert if fundingVault doesn't support asset()
        if (fundingVault != address(0) && ERC4626(targetVault).asset() != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }

        //Check that the AP has enough base asset in the funding vault for the order
        if (fundingVault == address(0) && ERC20(ERC4626(targetVault).asset()).balanceOf(msg.sender) < quantity) {
            revert NotEnoughBaseAssetToOrder();
        } else if(fundingVault != address(0) && ERC4626(fundingVault).maxWithdraw(msg.sender) < quantity) {
            revert NotEnoughBaseAssetToOrder();
        }

        // Emit the order creation event, used for matching orders
        emit APOrderCreated(numOrders, targetVault, msg.sender, fundingVault, expiry, tokensRequested, tokenRatesRequested, quantity);
        // Set the quantity of the order
        APOrder memory order = APOrder(numOrders, targetVault, msg.sender, fundingVault, expiry, tokensRequested, tokenRatesRequested);
        orderHashToRemainingQuantity[getOrderHash(order)] = quantity;
        // Return the new order's ID and increment the order counter
        return (numOrders++);
    }

    /// @notice allocate the entirety of a given order
    function allocateOrder(APOrder memory order) public {
        allocateOrder(order, orderHashToRemainingQuantity[getOrderHash(order)]);
    }

    /// @notice allocate a specific quantity of a given order
    function allocateOrder(APOrder memory order, uint256 quantity) public {
        // Check for order expiry, 0 expiries live forever
        if (order.expiry != 0 && block.timestamp > order.expiry) {
            revert OrderExpired();
        }

        bytes32 orderHash = getOrderHash(order);
        uint256 remainingQuantity = orderHashToRemainingQuantity[orderHash];

        // Zero orders have been completely filled, cancelled, or never existed
        if (remainingQuantity == 0) {
            revert OrderDoesNotExist();
        }
        if (quantity > remainingQuantity) {
            revert NotEnoughRemainingQuantity();
        }

        //Check that the AP has enough base asset in the funding vault for the order
        if (order.fundingVault == address(0) && ERC20(ERC4626(order.targetVault).asset()).balanceOf(order.ap) < quantity) {
            revert NotEnoughBaseAssetToAllocate();
        } else if(order.fundingVault != address(0) && ERC4626(order.fundingVault).maxWithdraw(order.ap) < quantity) {
            revert NotEnoughBaseAssetToAllocate();
        }

        // Reduce the remaining quantity of the order
        orderHashToRemainingQuantity[orderHash] -= quantity;

        // if the fundingVault is set to 0, fund the fill directly via the base asset
        if (order.fundingVault == address(0)) {
            // Transfer the base asset from the AP to the orderbook
            ERC4626(order.targetVault).asset().safeTransferFrom(order.ap, address(this), quantity);
        } else {
            // Withdraw from the funding vault to the orderbook
            ERC4626(order.fundingVault).withdraw(quantity, address(this), order.ap);
        }

        for (uint256 i; i < order.tokenRatesRequested.length; ++i) {
            if (order.tokenRatesRequested[i] > ERC4626i(order.targetVault).previewRateAfterDeposit(order.tokensRequested[i], quantity)) {
                revert OrderConditionsNotMet();
            }
        }

        ERC4626(order.targetVault).asset().safeApprove(order.targetVault, 0);
        ERC4626(order.targetVault).asset().safeApprove(order.targetVault, quantity);

        // Deposit into the target vault
        ERC4626(order.targetVault).deposit(quantity, order.ap);

        emit APOrderFilled(order.orderID, quantity);
    }

    /// @notice fully allocate a selection of orders
    function allocateOrders(APOrder[] memory orders) public {
        uint256 len = orders.length;
        for (uint256 i = 0; i < len; ++i) {
            allocateOrder(orders[i]);
        }
    }

    /// @notice cancel an outstanding order
    function cancelOrder(APOrder memory order) public {
        // Check if the AP is the creator of the order
        if (order.ap != msg.sender) {
            revert NotOrderCreator();
        }
        bytes32 orderHash = getOrderHash(order);

        if (orderHashToRemainingQuantity[orderHash] > 0) {
            // Set the remaining quantity of the order to 0, effectively cancelling it
            orderHashToRemainingQuantity[orderHash] = 0;
            emit APOrderCancelled(order.orderID);
        }
    }

    /// @notice calculate the hash of an order
    function getOrderHash(APOrder memory order) public pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }
}
