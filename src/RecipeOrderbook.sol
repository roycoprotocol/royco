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

    /// @custom:field orderID Set to numOrders - 1 on order creation (zero-indexed)
    /// @custom:field targetMarketID The ID of the weiroll market which will be executed on fill
    /// @custom:field lp The address of the liquidity provider
    /// @custom:field fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @custom:field expiry The timestamp after which the order is considered expired
    /// @custom:field tokensRequested The incentive tokens requested by the LP
    /// @custom:field tokenRatesRequested The desired rewards per input token per second
    struct LPOrder {
        uint256 orderID;
        uint256 targetMarketID;
        address lp;
        address fundingVault;
        uint256 expiry;
        address[] tokensRequested;
        uint256[] tokenAmountsRequested;
    }

    /// @custom:field targetMarketID The ID of the weiroll market which will be executed on fill
    /// @custom:field expiry The timestamp after which the order is considered expired
    /// @custom:field quantity The total amount of input tokens to be deposited
    /// @custom:field remainingQuantity The amount of input tokens remaining to be deposited
    /// @custom:field tokensOffered The incentive tokens offered by the IP
    /// @custom:field tokenAmountsOffered The amount of each token offered by the IP
    /// @custom:field tokenToFrontendFeeAmount The amount of each token to be sent to the frontend fee recipient
    struct IPOrder {
        uint256 targetMarketID;
        uint256 expiry;
        uint256 quantity;
        uint256 remainingQuantity;
        address[] tokensOffered;
        mapping(address => uint256) tokenAmountsOffered;
        mapping(address => uint256) tokenToFrontendFeeAmount;
    }

    /// @custom:field weirollCommands The weiroll script that will be executed on an LP's weiroll wallet after receiving the inputToken
    /// @custom:field weirollState State of the weiroll VM, necessary for executing the weiroll script
    struct Recipe {
        bytes32[] weirollCommands;
        bytes[] weirollState;
    }

    /// @custom:field inputToken The token that will be deposited into the user's weiroll wallet for use in the recipe
    /// @custom:field lockupTime The time in seconds that the user's weiroll wallet will be locked up for after deposit
    /// @custom:field frontendFee The fee that the frontend will take from IP incentives, 1e18 == 100% fee
    /// @custom:field depositRecipe The weiroll recipe that will be executed after the inputToken is transferred to the wallet
    /// @custom:field withdrawRecipe The weiroll recipe that may be executed after lockupTime has passed to unwind a user's position
    struct WeirollMarket {
        ERC20 inputToken;
        uint256 lockupTime;
        uint256 frontendFee;
        Recipe depositRecipe;
        Recipe withdrawRecipe;
    }

    /// @notice The address of the WeirollWallet implementation contract for use with ClonesWithImmutableArgs
    address public immutable WEIROLL_WALLET_IMPLEMENTATION;

    /// @notice The number of LP orders that have been created
    uint256 public numLPOrders;
    /// @notice The number of IP orders that have been created
    uint256 public numIPOrders;
    /// @notice The number of unique weiroll markets added
    uint256 public numMarkets;

    /// @notice The percent deducted from the IP's incentive amount and sent to protocolFeeRecipient
    uint256 public protocolFee; // 1e18 == 100% fee
    address public protocolFeeRecipient;

    /// @notice Markets can opt into a higher frontend fee to incentivize quick discovery but cannot go below this minimum
    uint256 public minimumFrontendFee; // 1e18 == 100% fee

    /// @notice Holds all WeirollMarket structs
    mapping(uint256 => WeirollMarket) public marketIDToWeirollMarket;
    /// @notice Holds all LPOrder structs
    mapping(uint256 => IPOrder) public orderIDToIPOrder;
    /// @notice Tracks the unfilled quantity of each LP order
    mapping(bytes32 => uint256) public orderHashToRemainingQuantity;

    /// @param _weirollWalletImplementation The address of the WeirollWallet implementation contract
    /// @param _protocolFee The percent deducted from the IP's incentive amount and sent to protocolFeeRecipient
    /// @param _minimumFrontendFee The minimum frontend fee that a market can set
    /// @param _owner The address that will be set as the owner of the contract
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

    /// @custom:field marketID The ID of the newly created market
    /// @custom:field inputToken The token that will be deposited into the user's weiroll wallet for use in the recipe
    /// @custom:field lockupTime The time in seconds that the user's weiroll wallet will be locked up for after deposit
    /// @custom:field frontendFee The fee paid to the frontend out of IP incentives
    event MarketCreated(uint256 indexed marketID, address indexed inputToken, uint256 lockupTime, uint256 frontendFee);

    /// @param orderID Set to numOrders - 1 on order creation (zero-indexed), ordered separately for LP and IP orders
    /// @param targetMarketID The ID of the weiroll market which will be executed on fill
    /// @param lp The address of the liquidity provider
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @param expiry The timestamp after which the order is considered expired
    /// @param tokensRequested The incentive tokens requested by the LP
    /// @param tokenRatesRequested The desired rewards per input token per second
    /// @param quantity The total amount of input tokens to be deposited
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

    /// @param orderID Set to numOrders - 1 on order creation (zero-indexed), ordered separately for LP and IP orders
    /// @param targetMarketID The ID of the weiroll market which will be executed on fill
    /// @param ip The address of the incentive provider
    /// @param expiry The timestamp after which the order is considered expired
    /// @param tokensOffered The incentive tokens offered by the IP
    /// @param tokenAmountsOffered The amount of each token offered by the IP
    /// @param quantity The total amount of input tokens to be deposited
    event IPOrderCreated(
        uint256 indexed orderID,
        uint256 indexed targetMarketID,
        address indexed ip,
        uint256 expiry,
        address[] tokensOffered,
        uint256[] tokenAmountsOffered,
        uint256 quantity
    );

    /// @param IPOrderID The ID of the IP order that was filled
    /// @param lp The address of the liquidity provider that filled the order
    /// @param quantity The amount of input tokens that were deposited
    event IPOrderFilled(uint256 indexed IPOrderID, address indexed lp, uint256 quantity);

    /// @param LPOrderID The ID of the LP order that was filled
    /// @param ip The address of the incentive provider that filled the order
    /// @param quantity The amount of input tokens that were deposited
    event LPOrderFilled(uint256 indexed LPOrderID, address indexed ip, uint256 quantity);

    /// @param IPOrderID The ID of the IP order that was cancelled
    event IPOrderCancelled(uint256 indexed IPOrderID);
    /// @param LPOrderID The ID of the LP order that was cancelled
    event LPOrderCancelled(uint256 indexed LPOrderID);

    // TODO claim fees event

    // Errors //TODO clean up
    error OrderExpired();
    error NotEnoughRemainingQuantity();
    error MismatchedBaseAsset();
    // error OrderDoesNotExist();
    error MarketDoesNotExist();
    error CannotPlaceExpiredOrder();
    // error OrderConditionsNotMet();
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

    /// @notice Create a new LP order. Order params will be emitted in an event while only the hash of the order and order quantity is stored onchain
    /// @dev LP orders are funded via approvals to ensure multiple orders can be placed off of a single input
    /// @dev Setting an expiry of 0 means the order never expires
    /// @param targetMarketID The ID of the weiroll market which will be executed on fill
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from, if set to 0, the LP will deposit the base asset directly
    /// @param quantity The total amount of input tokens to be deposited
    /// @param expiry The timestamp after which the order is considered expired
    /// @param tokensRequested The incentive token addresses requested by the LP in order to satisfy the order
    /// @param tokenAmountsRequested The amount of each token requested by the LP in order to satisfy the order
    function createLPOrder(
        uint256 targetMarketID,
        address fundingVault,
        uint256 quantity,
        uint256 expiry,
        address[] memory tokensRequested,
        uint256[] memory tokenAmountsRequested
    ) public returns (uint256) {
        // Check order isn't expired (expiries of 0 live forever)
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOrder();
        }
        // Check order isn't empty
        if (quantity == 0) {
            revert CannotPlaceZeroQuantityOrder();
        }
        // Check token and price arrays are the same length
        if (tokensRequested.length != tokenAmountsRequested.length) {
            revert ArrayLengthMismatch();
        }

        address targetBaseToken = marketIDToWeirollMarket[targetMarketID].inputToken;
        // If placing the order without a funding vault...
        if (fundingVault == address(0)) {
            if (ERC20(targetBaseToken).balanceOf(msg.sender) < quantity) {
                revert NotEnoughBaseAsset();
            }
            if (ERC20(targetBaseToken).allowance(msg.sender, address(this)) < quantity) {
                revert InsufficientApproval();
            }
        } else {
            // If placing the order with a funding vault...
            if (quantity > ERC4626(fundingVault).maxWithdraw(msg.sender)) {
                revert NotEnoughBaseAssetInVault();
            }
            if (
                ERC4626(fundingVault).allowance(msg.sender, address(this))
                    < ERC4626(fundingVault).previewWithdraw(quantity)
            ) {
                revert InsufficientApproval();
            }
            if (targetBaseToken != ERC4626(fundingVault).asset()) {
                revert MismatchedBaseAsset();
            }
        }

        /// @dev LPOrder events are stored in events and do not exist onchain outside of the orderHashToRemainingQuantity mapping
        emit LPOrderCreated(
            numLPOrders,
            targetMarketID,
            msg.sender,
            fundingVault,
            expiry,
            tokensRequested,
            tokenAmountsRequested,
            quantity
        );

        // Map the order hash to the order quantity
        LPOrder memory order =
            LPOrder(numOrders, targetMarketID, msg.sender, fundingVault, expiry, tokensRequested, tokenAmountsRequested);
        orderHashToRemainingQuantity[getOrderHash(order)] = quantity;
        return (numOrders++);
    }

    /// @notice Create a new IP order, transferring the IP's incentives to the orderbook and putting all the order params in contract storage
    /// @dev IP must approve all tokens to be spent by the orderbook before calling this function
    /// @param targetMarketID The ID of the weiroll market which will be executed on fill
    /// @param quantity The total amount of input tokens to be deposited
    /// @param expiry The timestamp after which the order is considered expired
    /// @param tokensOffered The incentive token addresses offered by the IP
    /// @param tokenAmounts The amount of each token offered by the IP
    function createIPOrder(
        uint256 targetMarketID,
        uint256 quantity,
        uint256 expiry,
        address[] memory tokensOffered,
        uint256[] memory tokenAmounts
    ) public returns (uint256) {
        // Check that the target market exists
        if (targetMarketID >= numMarkets) {
            revert MarketDoesNotExist();
        }
        // Check that the order isn't expired
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOrder();
        }
        // Check that the token and price arrays are the same length
        if (tokensOffered.length != tokenAmounts.length) {
            revert ArrayLengthMismatch();
        }

        // Create the order
        IPOrder storage order = orderIDToIPOrder[numOrders];
        order.targetMarketID = targetMarketID;
        order.quantity = quantity;
        order.remainingQuantity = quantity;
        order.expiry = expiry;
        order.tokensOffered = tokensOffered;

        // Transfer the IP's incentives to the orderbook and set aside fees
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

        emit IPOrderCreated(numOrders, targetMarketID, msg.sender, expiry, tokensOffered, tokenAmounts, quantity);

        return (numOrders++);
    }

    /// @notice Fill an IP order, transferring the IP's incentives to the LP, withdrawing the LP from their funding vault into a fresh weiroll wallet, and executing the weiroll recipe
    /// @param orderID The ID of the IP order to fill
    /// @param fillAmount The amount of input tokens to fill the order with
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @param frontendFeeRecipient The address that will receive the frontend fee
    function fillIPOrder(uint256 orderID, uint256 fillAmount, address fundingVault, address frontendFeeRecipient)
        public
    {
        // Retreive the IPOrder and WeirollMarket structs
        IPOrder storage order = orderIDToIPOrder[orderID];
        WeirollMarket memory market = marketIDToWeirollMarket[order.targetMarketID];

        // Check that the order isn't expired
        if (order.expiry != 0 && block.timestamp >= order.expiry) {
            revert OrderExpired();
        }
        // Check that the order has enough remaining quantity
        if (order.remainingQuantity < fillAmount) {
            revert NotEnoughRemainingQuantity();
        }
        // Check that the order's base asset matches the market's base asset
        if (market.inputToken != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }
        // Check that the order isn't empty
        if (fillAmount == 0) {
            revert CannotPlaceZeroQuantityOrder();
        }

        // Update the order's remaining quantity before interacting with external contracts
        order.remainingQuantity -= fillAmount;

        // Create a new weiroll wallet for the LP with an appropriate unlock time
        uint256 unlockTime = block.timestamp + market.lockupTime;
        WeirollWallet wallet = WeirollWallet(
            WEIROLL_WALLET_IMPLEMENTATION.clone(abi.encodePacked(msg.sender, address(this), fillAmount, unlockTime))
        );

        // Transfer the IP's incentives to the LP and set aside fees
        for (uint256 i = 0; i < order.tokensOffered.length; ++i) {
            address token = order.tokensOffered[i];
            uint256 fillPercentage = fillAmount.divWadDown(order.quantity);
            // Fees are taken as a percentage of the incentive amount
            uint256 frontendFeeAmount = order.tokenToFrontendFeeAmount[token].mulWadDown(fillPercentage);
            uint256 incentiveAmount = order.tokenAmountsOffered[token].mulWadDown(fillPercentage);

            ERC20(token).safeTransfer(msg.sender, incentiveAmount); //TODO: forfeit ordertype
            ERC20(token).safeTransfer(frontendFeeRecipient, frontendFeeAmount);
        }

        // If the fundingVault is set to 0, fund the fill directly via the base asset
        if (fundingVault != address(0)) {
            ERC20(market.inputToken).safeTransferFrom(address(wallet), msg.sender, fillAmount);
        } else {
            // Withdraw the LP from the funding vault into the wallet
            ERC4626(fundingVault).withdraw(fillAmount, address(wallet), msg.sender);
        }

        // Now that 
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

        // if the fundingVault is set to 0, fund the fill directly via the base asset
        if (order.fundingVault == address(0)) {
            // Transfer the base asset from the LP to the target vault
            ERC20(market.inputToken).safeTransferFrom(order.lp, address(wallet), fillAmount);
        } else {
            // Withdraw from the funding vault
            ERC4626(order.fundingVault).withdraw(fillAmount, address(wallet), order.lp);
        }

        wallet.executeWeiroll(market.depositRecipe.weirollCommands, market.depositRecipe.weirollState);
    }

    /// @notice sets the protocol fee recipient, taken on all fills
    function setProtocolFeeRecipient(address _protocolFeeRecipient) public onlyOwner {
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    /// @notice sets the protocol fee rate, taken on all fills
    /// @param _protocolFee The percent deducted from the IP's incentive amount and sent to protocolFeeRecipient, 1e18 == 100% fee
    function setProtocolFee(uint256 _protocolFee) public onlyOwner {
        protocolFee = _protocolFee;
    }

    /// @notice sets the minimum frontend fee that a market can set and is paid to w
    function setMinimumFrontendFee(uint256 _minimumFrontendFee) public onlyOwner {
        minimumFrontendFee = _minimumFrontendFee;
    }

    /// @notice calculates the hash of an order
    function getOrderHash(LPOrder memory order) public pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }
}
