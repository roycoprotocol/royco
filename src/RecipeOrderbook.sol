// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {ERC4626} from "lib/solmate/src/tokens/ERC4626.sol";
import {ClonesWithImmutableArgs} from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import {WeirollWallet} from "src/WeirollWallet.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {Ownable2Step, Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract RecipeOrderbook is Ownable2Step {
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    struct LPOrder {
        uint256 orderID;
        uint256 targetMarketID;
        address lp;
        address fundingVault;
        uint256 expiry;
        address[] tokensRequested;
        uint256[] tokenAmountsRequested;
    }

    struct IPOrder {
        uint256 targetMarketID;
        uint256 expiry;
        uint256 quantity;
        uint256 remainingQuantity;
        address[] tokensOffered;
        mapping(address => uint256) tokenAmountsOffered;
        mapping(address => uint256) tokenToFrontendFeeAmount;
    }

    struct Recipe {
        bytes32[] weirollCommands;
        bytes[] weirollState;
    }

    struct WeirollMarket {
        ERC20 inputToken;
        uint256 lockupTime;
        uint256 frontendFee;
        Recipe depositRecipe;
        Recipe withdrawRecipe;
    }

    // Contract State

    uint256 private constant PRECISION = 1e18;

    address public immutable WEIROLL_WALLET_IMPLEMENTATION;

    uint256 public numOrders;
    uint256 public numMarkets;

    address public protocolFeeRecipient;

    uint256 public protocolFee; // 1e18 == 100% fee
    uint256 public minimumFrontendFee; // 1e18 == 100% fee

    mapping(uint256 => WeirollMarket) public marketIDToWeirollMarket;
    mapping(uint256 => IPOrder) public orderIDToIPOrder;
    mapping(bytes32 => uint256) public orderHashToRemainingQuantity;

    constructor(address _weirollWalletImplementation, uint256 _protocolFee, uint256 _minimumFrontendFee, address _owner)
        Ownable(_owner)
    {
        WEIROLL_WALLET_IMPLEMENTATION = _weirollWalletImplementation;
        protocolFee = _protocolFee;
        minimumFrontendFee = _minimumFrontendFee;

        // Redundant
        numOrders = 0;
        numMarkets = 0;
    }

    event MarketCreated(uint256 indexed marketID, address indexed inputToken, uint256 lockupTime, uint256 frontendFee);

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
        uint256 indexed targetMarketID,
        address indexed ip,
        uint256 expiry,
        address[] tokensOffered,
        uint256[] tokenAmountsOffered,
        uint256 quantity
    );

    event IPOrderFilled(uint256 indexed orderID, address indexed lp, uint256 quantity);
    event LPOrderFilled(uint256 indexed orderID, address indexed ip, uint256 quantity);

    event IPOrderCancelled(uint256 indexed orderID);
    event LPOrderCancelled(uint256 indexed orderID);

    // TODO claim fees event

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
    error FrontendFeeTooLow();

    /// @notice Create a new recipe market
    /// @param inputToken The token that will be deposited into the user's weiroll wallet for use in the recipe
    /// @param lockupTime The time in seconds that the user's weiroll wallet will be locked up for after deposit
    /// @param frontendFee The fee that the frontend will take from the user's weiroll wallet, 1e18 == 100% fee
    /// @param depositRecipe The weiroll script that will be executed after the inputToken is transferred to the wallet
    /// @param withdrawRecipe The weiroll script that may be executed after lockupTime has passed to unwind a user's position
    function createMarket(
        address inputToken,
        uint256 lockupTime,
        uint256 frontendFee,
        Recipe calldata depositRecipe,
        Recipe calldata withdrawRecipe
    ) public returns (uint256) {
        if (frontendFee < minimumFrontendFee) {
            revert FrontendFeeTooLow();
        }

        marketIDToWeirollMarket[numMarkets] =
            WeirollMarket(ERC20(inputToken), lockupTime, frontendFee, depositRecipe, withdrawRecipe);

        emit MarketCreated(numMarkets, inputToken, lockupTime, frontendFee);
        return (numMarkets++);
    }

    /// @dev Setting an expiry of 0 means the order never expires
    function createLPOrder(
        uint256 targetMarketID,
        address fundingVault,
        uint256 quantity,
        uint256 expiry,
        address[] memory tokensRequested,
        uint256[] memory tokenAmountsRequested
    ) public returns (uint256) {
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
        if (
            ERC4626(fundingVault).allowance(msg.sender, address(this)) < ERC4626(fundingVault).previewWithdraw(quantity)
        ) {
            revert InsufficientApproval();
        }
        if (marketIDToWeirollMarket[targetMarketID].inputToken != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }

        LPOrder memory order =
            LPOrder(numOrders, targetMarketID, msg.sender, fundingVault, expiry, tokensRequested, tokenAmountsRequested);
        orderHashToRemainingQuantity[getOrderHash(order)] = quantity;
        return (numOrders++);
    }

    /// @dev IP must approve all tokens to be spent by the orderbook before calling this function
    function createIPOrder(
        uint256 targetMarketID,
        uint256 quantity,
        uint256 expiry,
        address[] memory tokensOffered,
        uint256[] memory tokenAmounts
    ) public returns (uint256) {
        if (targetMarketID >= numMarkets) {
            revert MarketDoesNotExist();
        }
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOrder();
        }
        if (tokensOffered.length != tokenAmounts.length) {
            revert ArrayLengthMismatch();
        }

        IPOrder storage order = orderIDToIPOrder[numOrders];

        order.targetMarketID = targetMarketID;
        order.quantity = quantity;
        order.remainingQuantity = quantity;
        order.expiry = expiry;
        order.tokensOffered = tokensOffered;
        for (uint256 i = 0; i < tokensOffered.length; ++i) {
            uint256 amount = tokenAmounts[i];
            uint256 protocolFeeAmount = amount.mulWadDown(protocolFee);
            uint256 frontendFeeAmount = amount.mulWadDown(marketIDToWeirollMarket[targetMarketID].frontendFee);
            uint256 incentiveAmount = amount - protocolFeeAmount - frontendFeeAmount;

            order.tokenAmountsOffered[tokensOffered[i]] = incentiveAmount;

            order.tokenToFrontendFeeAmount[tokensOffered[i]] = frontendFeeAmount;
            // Take protocol fee
            ERC20(tokensOffered[i]).safeTransferFrom(msg.sender, protocolFeeRecipient, protocolFeeAmount);
            // Transfer frontend fee + incentiveAmount to orderbook
            ERC20(tokensOffered[i]).safeTransferFrom(msg.sender, address(this), incentiveAmount + frontendFeeAmount); //TODO: handle points
        }
        return (numOrders++);
    }

    function fillIPOrder(uint256 orderID, uint256 fillAmount, address fundingVault, address frontendFeeRecipient)
        public
    {
        IPOrder storage order = orderIDToIPOrder[orderID];
        WeirollMarket memory market = marketIDToWeirollMarket[order.targetMarketID];

        if (order.expiry != 0 && block.timestamp >= order.expiry) {
            revert OrderExpired();
        }
        if (order.remainingQuantity < fillAmount) {
            revert NotEnoughRemainingQuantity();
        }
        if (market.inputToken != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }
        if (fillAmount == 0) {
            revert CannotPlaceZeroQuantityOrder();
        }

        order.remainingQuantity -= fillAmount;

        uint256 unlockTime = block.timestamp + market.lockupTime;
        WeirollWallet wallet = WeirollWallet(
            WEIROLL_WALLET_IMPLEMENTATION.clone(abi.encodePacked(msg.sender, address(this), fillAmount, unlockTime))
        );

        for (uint256 i = 0; i < order.tokensOffered.length; ++i) {
            address token = order.tokensOffered[i];
            uint256 fillPercentage = fillAmount.divWadDown(order.quantity);
            uint256 frontendFeeAmount = order.tokenToFrontendFeeAmount[token].mulWadDown(fillPercentage);
            uint256 incentiveAmount = order.tokenAmountsOffered[token].mulWadDown(fillPercentage);

            ERC20(token).safeTransfer(msg.sender, incentiveAmount); //TODO: forfeit ordertype
            ERC20(token).safeTransfer(frontendFeeRecipient, frontendFeeAmount);
        }

        if (fundingVault != address(0)) {
            ERC20(market.inputToken).safeTransferFrom(address(wallet), msg.sender, fillAmount);
        } else {
            ERC4626(fundingVault).withdraw(fillAmount, address(wallet), msg.sender);
        }

        wallet.executeWeiroll(market.depositRecipe.weirollCommands, market.depositRecipe.weirollState);
    }

    /// @dev IP must approve all tokens to be spent (both fills + fees!) by the orderbook before calling this function
    function fillLPOrder(LPOrder calldata order, uint256 fillAmount, address frontendFeeRecipient) public {
        if (order.expiry != 0 && block.timestamp >= order.expiry) revert OrderExpired();

        bytes32 orderHash = getOrderHash(order);
        if (fillAmount > orderHashToRemainingQuantity[orderHash]) revert NotEnoughRemainingQuantity();
        orderHashToRemainingQuantity[orderHash] -= fillAmount;

        uint256 len = order.tokensRequested.length;
        for (uint256 i = 0; i < len; ++i) {
            //safetransfer the token to the LP
            ERC20(order.tokensRequested[i]).safeTransferFrom(msg.sender, order.lp, order.tokenAmountsRequested[i]);

            //safetransfer the fee to the frontendFeeRecipient
            ERC20(order.tokensRequested[i]).safeTransferFrom(
                msg.sender, frontendFeeRecipient, order.tokenAmountsRequested[i].mulWadDown(minimumFrontendFee)
            );
        }

        WeirollMarket memory market = marketIDToWeirollMarket[order.targetMarketID];
        uint256 unlockTime = block.timestamp + market.lockupTime;
        WeirollWallet wallet = WeirollWallet(
            WEIROLL_WALLET_IMPLEMENTATION.clone(abi.encodePacked(order.lp, address(this), fillAmount, unlockTime))
        );

        if (order.fundingVault == address(0)) {
            ERC20(market.inputToken).safeTransferFrom(order.lp, address(wallet), fillAmount);
        } else {
            ERC4626(order.fundingVault).withdraw(fillAmount, address(wallet), order.lp);
        }

        wallet.executeWeiroll(market.depositRecipe.weirollCommands, market.depositRecipe.weirollState);
    }

    function setProtocolFeeRecipient(address _protocolFeeRecipient) public onlyOwner {
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    function setProtocolFee(uint256 _protocolFee) public onlyOwner {
        protocolFee = _protocolFee;
    }

    function setMinimumFrontendFee(uint256 _minimumFrontendFee) public onlyOwner {
        minimumFrontendFee = _minimumFrontendFee;
    }

    function getOrderHash(LPOrder memory order) public pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }
}
