// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { WeirollWallet } from "src/WeirollWallet.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { Ownable2Step, Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { Points } from "src/Points.sol";
import { ReentrancyGuard } from "lib/solmate/src/utils/ReentrancyGuard.sol";
import { PointsFactory } from "src/PointsFactory.sol";

enum RewardStyle {
    Upfront,
    Arrear,
    Forfeitable
}

/// @title RecipeOrderbook
/// @author CopyPaste, corddry, ShivaanshK
/// @notice Orderbook Contract for Incentivizing AP/IPs to participate in "recipes" which perform arbitrary actions
contract RecipeOrderbook is Ownable2Step, ReentrancyGuard {
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @custom:field orderID Set to numAPOrders - 1 on order creation (zero-indexed)
    /// @custom:field targetMarketID The ID of the weiroll market which will be executed on fill
    /// @custom:field ap The address of the action provider
    /// @custom:field fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @custom:field expiry The timestamp after which the order is considered expired
    /// @custom:field tokensRequested The incentive tokens requested by the AP
    /// @custom:field tokenAmountsRequested The desired rewards per input token
    struct APOrder {
        uint256 orderID;
        uint256 targetMarketID;
        address ap;
        address fundingVault;
        uint256 quantity;
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
        address ip;
        uint256 expiry;
        uint256 quantity;
        uint256 remainingQuantity;
        address[] tokensOffered;
        mapping(address => uint256) tokenAmountsOffered; // amounts to be released to AP (per incentive)
        mapping(address => uint256) tokenToProtocolFeeAmount; // amounts to be released to protocolFeeClaimant (per incentive)
        mapping(address => uint256) tokenToFrontendFeeAmount; // amounts to be released to frontend provider (per incentive)
    }

    /// @custom:field weirollCommands The weiroll script that will be executed on an AP's weiroll wallet after receiving the inputToken
    /// @custom:field weirollState State of the weiroll VM, necessary for executing the weiroll script
    struct Recipe {
        bytes32[] weirollCommands;
        bytes[] weirollState;
    }

    /// @custom:field tokens Tokens offered as incentives
    /// @custom:field amounts The amount of tokens offered for each token
    /// @custom:field ip The incentives provider
    struct LockedRewardParams {
        address[] tokens;
        uint256[] amounts;
        address ip;
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
        RewardStyle rewardStyle;
    }

    /// @notice The address of the WeirollWallet implementation contract for use with ClonesWithImmutableArgs
    address public immutable WEIROLL_WALLET_IMPLEMENTATION;

    /// @notice The address of the PointsFactory contract
    address public immutable POINTS_FACTORY;

    /// @notice The number of AP orders that have been created
    uint256 public numAPOrders;
    /// @notice The number of IP orders that have been created
    uint256 public numIPOrders;
    /// @notice The number of unique weiroll markets added
    uint256 public numMarkets;

    /// @notice The percent deducted from the IP's incentive amount and claimable by protocolFeeClaimant
    uint256 public protocolFee; // 1e18 == 100% fee
    address public protocolFeeClaimant;

    /// @notice Markets can opt into a higher frontend fee to incentivize quick discovery but cannot go below this minimum
    uint256 public minimumFrontendFee; // 1e18 == 100% fee

    /// @notice Holds all WeirollMarket structs
    mapping(uint256 => WeirollMarket) public marketIDToWeirollMarket;

    /// @notice Holds all IPOrder structs
    mapping(uint256 => IPOrder) public orderIDToIPOrder;
    /// @notice Tracks the unfilled quantity of each AP order
    mapping(bytes32 => uint256) public orderHashToRemainingQuantity;

    // Tracks the locked incentives associated with a weiroll wallet
    mapping(address => LockedRewardParams) public weirollWalletToLockedRewardParams;

    // Structure to store each fee claimant's accrued fees for a particular token (claimant => token => feesAccrued)
    mapping(address => mapping(address => uint256)) public feeClaimantToTokenToAmount;

    /// @param _weirollWalletImplementation The address of the WeirollWallet implementation contract
    /// @param _protocolFee The percent deducted from the IP's incentive amount and claimable by protocolFeeClaimant
    /// @param _minimumFrontendFee The minimum frontend fee that a market can set
    /// @param _owner The address that will be set as the owner of the contract
    constructor(
        address _weirollWalletImplementation,
        uint256 _protocolFee,
        uint256 _minimumFrontendFee,
        address _owner,
        address _pointsFactory
    )
        Ownable(_owner)
    {
        WEIROLL_WALLET_IMPLEMENTATION = _weirollWalletImplementation;
        POINTS_FACTORY = _pointsFactory;
        protocolFee = _protocolFee;
        protocolFeeClaimant = _owner;
        minimumFrontendFee = _minimumFrontendFee;
    }

    /// @custom:field marketID The ID of the newly created market
    /// @custom:field inputToken The token that will be deposited into the user's weiroll wallet for use in the recipe
    /// @custom:field lockupTime The time in seconds that the user's weiroll wallet will be locked up for after deposit
    /// @custom:field frontendFee The fee paid to the frontend out of IP incentives
    /// @custom:field rewardStyle Whether the rewards are paid at the beginning, locked until the end, or forfeitable until the end
    event MarketCreated(uint256 indexed marketID, address indexed inputToken, uint256 lockupTime, uint256 frontendFee, RewardStyle rewardStyle);

    /// @param orderID Set to numAPOrders - 1 on order creation (zero-indexed), ordered separately for AP and IP orders
    /// @param targetMarketID The ID of the weiroll market which will be executed on fill
    /// @param ap The address of the action provider
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @param expiry The timestamp after which the order is considered expired
    /// @param tokensRequested The incentive tokens requested by the AP
    /// @param tokenAmountsRequested The desired rewards per input token
    /// @param quantity The total amount of input tokens to be deposited
    event APOrderCreated(
        uint256 indexed orderID,
        uint256 indexed targetMarketID,
        address indexed ap,
        address fundingVault,
        uint256 quantity,
        uint256 expiry,
        address[] tokensRequested,
        uint256[] tokenAmountsRequested
    );

    /// @param orderID Set to numIPOrders - 1 on order creation (zero-indexed), ordered separately for AP and IP orders
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
    /// @param ap The address of the action provider that filled the order
    /// @param remainingQuantity The amount of input tokens the order can still be filled with
    event IPOrderFilled(
        uint256 indexed marketID, uint256 indexed IPOrderID, address indexed ap, uint256 fillAmount, uint256 remainingQuantity, address weirollWallet
    );

    /// @param APOrderID The ID of the AP order that was filled
    /// @param ip The address of the incentive provider that filled the order
    /// @param remainingQuantity The amount of input tokens the order can still be filled with
    event APOrderFilled(
        uint256 indexed marketID, uint256 indexed APOrderID, address indexed ip, uint256 fillAmount, uint256 remainingQuantity, address weirollWallet
    );

    /// @param IPOrderID The ID of the IP order that was cancelled
    event IPOrderCancelled(uint256 indexed IPOrderID);
    /// @param APOrderID The ID of the AP order that was cancelled
    event APOrderCancelled(uint256 indexed APOrderID);

    event FeesClaimed(address indexed claimant, uint256 amount);

    /// @notice emitted when trying to fill an order that has expired
    error OrderExpired();
    /// @notice emitted when trying to cancel an order that has an indefinite expiry
    error OrderCannotExpire();
    /// @notice emitted when trying to fill an order with more input tokens than the remaining order quantity
    error NotEnoughRemainingQuantity();
    /// @notice emitted when the base asset of the target vault and the funding vault do not match
    error MismatchedBaseAsset();
    /// @notice emitted if a market with the given ID does not exist
    error MarketDoesNotExist();
    /// @notice emitted when trying to place an order with an expiry in the past
    error CannotPlaceExpiredOrder();
    /// @notice emitted when trying to place an order with a quantity of 0
    error CannotPlaceZeroQuantityOrder();
    /// @notice emitted when token and amount arrays are not the same length
    error ArrayLengthMismatch();
    /// @notice emitted when the frontend fee is below the minimum
    error FrontendFeeTooLow();
    /// @notice emitted when trying to forfeit a wallet that is not owned by the caller
    error NotOwner();
    /// @notice emitted when trying to claim rewards of a wallet that is locked
    error WalletLocked();
    /// @notice Emitted when trying to start a rewards campaign with a non-existant token
    error TokenDoesNotExist();
    /// @notice Emitted when sum of protocolFee and frontendFee is greater than 100% (1e18)
    error TotalFeeTooHigh();
    /// @notice emitted when trying to fill an order that doesn't exist anymore/yet
    error CannotFillZeroQuantityOrder();

    // modifier to check if msg.sender is owner of a weirollWallet
    modifier isWeirollOwner(address weirollWallet) {
        if (WeirollWallet(payable(weirollWallet)).owner() != msg.sender) {
            revert NotOwner();
        }
        _;
    }

    // modifier to check if the weiroll wallet is unlocked
    modifier weirollIsUnlocked(address weirollWallet) {
        if (WeirollWallet(payable(weirollWallet)).lockedUntil() > block.timestamp) {
            revert WalletLocked();
        }
        _;
    }

    // Getters to access nested mappings
    function getTokenAmountsOfferedForIPOrder(uint256 orderId, address tokenAddress) external view returns (uint256) {
        return orderIDToIPOrder[orderId].tokenAmountsOffered[tokenAddress];
    }

    function getTokenToProtocolFeeAmountForIPOrder(uint256 orderId, address tokenAddress) external view returns (uint256) {
        return orderIDToIPOrder[orderId].tokenToProtocolFeeAmount[tokenAddress];
    }

    function getTokenToFrontendFeeAmountForIPOrder(uint256 orderId, address tokenAddress) external view returns (uint256) {
        return orderIDToIPOrder[orderId].tokenToFrontendFeeAmount[tokenAddress];
    }

    // Single getter function that returns the entire LockedRewardParams struct as a tuple
    function getLockedRewardParams(address weirollWallet) external view returns (address[] memory tokens, uint256[] memory amounts, address ip) {
        LockedRewardParams storage params = weirollWalletToLockedRewardParams[weirollWallet];
        return (params.tokens, params.amounts, params.ip);
    }

    /// @notice Create a new recipe market
    /// @param inputToken The token that will be deposited into the user's weiroll wallet for use in the recipe
    /// @param lockupTime The time in seconds that the user's weiroll wallet will be locked up for after deposit
    /// @param frontendFee The fee that the frontend will take from the user's weiroll wallet, 1e18 == 100% fee
    /// @param depositRecipe The weiroll script that will be executed after the inputToken is transferred to the wallet
    /// @param withdrawRecipe The weiroll script that may be executed after lockupTime has passed to unwind a user's position
    /// @custom:field rewardStyle Whether the rewards are paid at the beginning, locked until the end, or forfeitable until the end
    /// @return marketID ID of the newly created market
    function createMarket(
        address inputToken,
        uint256 lockupTime,
        uint256 frontendFee,
        Recipe calldata depositRecipe,
        Recipe calldata withdrawRecipe,
        RewardStyle rewardStyle
    )
        public
        returns (uint256)
    {
        if (frontendFee < minimumFrontendFee) {
            revert FrontendFeeTooLow();
        } else if ((frontendFee + protocolFee) > 1e18) {
            // Sum of fees is too high
            revert TotalFeeTooHigh();
        }

        marketIDToWeirollMarket[numMarkets] = WeirollMarket(ERC20(inputToken), lockupTime, frontendFee, depositRecipe, withdrawRecipe, rewardStyle);

        emit MarketCreated(numMarkets, inputToken, lockupTime, frontendFee, rewardStyle);
        return (numMarkets++);
    }

    /// @notice Create a new AP order. Order params will be emitted in an event while only the hash of the order and order quantity is stored onchain
    /// @dev AP orders are funded via approvals to ensure multiple orders can be placed off of a single input
    /// @dev Setting an expiry of 0 means the order never expires
    /// @param targetMarketID The ID of the weiroll market which will be executed on fill
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from, if set to 0, the AP will deposit the base asset directly
    /// @param quantity The total amount of input tokens to be deposited
    /// @param expiry The timestamp after which the order is considered expired
    /// @param tokensRequested The incentive token addresses requested by the AP in order to satisfy the order
    /// @param tokenAmountsRequested The amount of each token requested by the AP in order to satisfy the order
    /// @return orderID ID of the newly created order
    function createAPOrder(
        uint256 targetMarketID,
        address fundingVault,
        uint256 quantity,
        uint256 expiry,
        address[] memory tokensRequested,
        uint256[] memory tokenAmountsRequested
    )
        public
        returns (uint256 orderID)
    {
        // Check market exists
        if (targetMarketID >= numMarkets) {
            revert MarketDoesNotExist();
        }
        // Check order isn't expired (expiries of 0 live forever)
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOrder();
        }
        // Check order isn't empty
        if (quantity < 1e6) {
            revert CannotPlaceZeroQuantityOrder();
        }
        // Check token and price arrays are the same length
        if (tokensRequested.length != tokenAmountsRequested.length) {
            revert ArrayLengthMismatch();
        }

        // NOTE: The cool use of short-circuit means this call can't revert if fundingVault doesn't support asset()
        if (fundingVault != address(0) && marketIDToWeirollMarket[targetMarketID].inputToken != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }

        /// @dev APOrder events are stored in events and do not exist onchain outside of the orderHashToRemainingQuantity mapping
        emit APOrderCreated(numAPOrders, targetMarketID, msg.sender, fundingVault, quantity, expiry, tokensRequested, tokenAmountsRequested);

        // Map the order hash to the order quantity
        APOrder memory order = APOrder(numAPOrders, targetMarketID, msg.sender, fundingVault, quantity, expiry, tokensRequested, tokenAmountsRequested);
        orderHashToRemainingQuantity[getOrderHash(order)] = quantity;
        return (numAPOrders++);
    }

    /// @notice Create a new IP order, transferring the IP's incentives to the orderbook and putting all the order params in contract storage
    /// @dev IP must approve all tokens to be spent by the orderbook before calling this function
    /// @param targetMarketID The ID of the weiroll market which will be executed on fill
    /// @param quantity The total amount of input tokens to be deposited
    /// @param expiry The timestamp after which the order is considered expired
    /// @param tokensOffered The incentive token addresses offered by the IP
    /// @param tokenAmounts The amount of each token offered by the IP
    /// @return marketID ID of the newly created market
    function createIPOrder(
        uint256 targetMarketID,
        uint256 quantity,
        uint256 expiry,
        address[] memory tokensOffered,
        uint256[] memory tokenAmounts
    )
        public
        returns (uint256 marketID)
    {
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
        // Check order isn't empty
        if (quantity < 1e6) {
            revert CannotPlaceZeroQuantityOrder();
        }

        // Create the order
        IPOrder storage order = orderIDToIPOrder[numIPOrders];
        order.targetMarketID = targetMarketID;
        order.ip = msg.sender;
        order.quantity = quantity;
        order.remainingQuantity = quantity;
        order.expiry = expiry;
        order.tokensOffered = tokensOffered;

        // Transfer the IP's incentives to the orderbook and set aside fees
        for (uint256 i = 0; i < tokensOffered.length; ++i) {
            uint256 amount = tokenAmounts[i];
            // Calculate incentive and fee breakdown
            uint256 protocolFeeAmount = amount.mulWadDown(protocolFee);
            uint256 frontendFeeAmount = amount.mulWadDown(marketIDToWeirollMarket[targetMarketID].frontendFee);
            uint256 incentiveAmount = amount - protocolFeeAmount - frontendFeeAmount;

            // Set appropriate amounts
            order.tokenToProtocolFeeAmount[tokensOffered[i]] = protocolFeeAmount;
            order.tokenToFrontendFeeAmount[tokensOffered[i]] = frontendFeeAmount;
            order.tokenAmountsOffered[tokensOffered[i]] = incentiveAmount;

            // Check if not points
            if (!PointsFactory(POINTS_FACTORY).isPointsProgram(tokensOffered[i])) {
                // Transfer frontend fee + protocol fee + incentiveAmount to orderbook
                address token = tokensOffered[i];
                // SafeTransferFrom does not check if a token address has any code, so we need to check it manually to prevent token deployment frontrunning
                if (token.code.length == 0) revert TokenDoesNotExist();
                ERC20(tokensOffered[i]).safeTransferFrom(msg.sender, address(this), incentiveAmount + protocolFeeAmount + frontendFeeAmount);
            }
        }

        emit IPOrderCreated(numIPOrders, targetMarketID, msg.sender, expiry, tokensOffered, tokenAmounts, quantity);

        return (numIPOrders++);
    }

    /// @param recipient The address to send fees to
    /// @param token The token address where fees are accrued in
    /// @param amount The amount of fees to award
    /// @param ip The incentive provider if awarding points
    function accountFee(address recipient, address token, uint256 amount, address ip) internal {
        //check to see the token is actually a points campaign
        if (PointsFactory(POINTS_FACTORY).isPointsProgram(token)) {
            // Points cannot be claimed and are rather directly awarded
            Points(token).award(recipient, amount, ip);
        } else {
            feeClaimantToTokenToAmount[recipient][token] += amount;
        }
    }

    /// @param token The token to claim fees for
    /// @param to The address to send fees claimed to
    function claimFees(address token, address to) public {
        uint256 amount = feeClaimantToTokenToAmount[msg.sender][token];
        feeClaimantToTokenToAmount[msg.sender][token] = 0;
        ERC20(token).safeTransfer(to, amount);
        emit FeesClaimed(msg.sender, amount);
    }

    /// @notice Fill an IP order, transferring the IP's incentives to the AP, withdrawing the AP from their funding vault into a fresh weiroll wallet, and
    /// executing the weiroll recipe
    /// @param orderID The ID of the IP order to fill
    /// @param fillAmount The amount of input tokens to fill the order with
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @param frontendFeeRecipient The address that will receive the frontend fee
    function fillIPOrder(uint256 orderID, uint256 fillAmount, address fundingVault, address frontendFeeRecipient) public {
        // Retreive the IPOrder and WeirollMarket structs
        IPOrder storage order = orderIDToIPOrder[orderID];
        WeirollMarket storage market = marketIDToWeirollMarket[order.targetMarketID];

        // Check that the order isn't expired
        if (order.expiry != 0 && block.timestamp > order.expiry) {
            revert OrderExpired();
        }
        // Check that the order has enough remaining quantity
        if (order.remainingQuantity < fillAmount && fillAmount != type(uint256).max) {
            revert NotEnoughRemainingQuantity();
        }
        if (fillAmount == type(uint256).max) {
            fillAmount = order.remainingQuantity;
        }

        // Check that the order's base asset matches the market's base asset
        if (fundingVault != address(0) && market.inputToken != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }
        // Check that the order isn't empty
        if (fillAmount == 0) {
            revert CannotPlaceZeroQuantityOrder();
        }

        // Calculate the percentage of the order the AP is filling
        uint256 fillPercentage = fillAmount.divWadDown(order.quantity);

        // Update the order's remaining quantity before interacting with external contracts
        order.remainingQuantity -= fillAmount;

        // Create a new weiroll wallet for the AP with an appropriate unlock time
        uint256 unlockTime = block.timestamp + market.lockupTime;

        // Create weiroll wallet to lock assets for recipe execution(s)
        bool forfeitable = market.rewardStyle == RewardStyle.Forfeitable;
        WeirollWallet wallet = WeirollWallet(
            payable(WEIROLL_WALLET_IMPLEMENTATION.clone(abi.encodePacked(msg.sender, address(this), fillAmount, unlockTime, forfeitable, order.targetMarketID)))
        );

        if (market.rewardStyle != RewardStyle.Upfront) {
            // If RewardStyle is either Forfeitable or Arrear
            // Create locked rewards params to account for payouts upon wallet unlocking
            LockedRewardParams memory params;
            params.tokens = order.tokensOffered;
            params.amounts = new uint256[](order.tokensOffered.length);
            params.ip = order.ip;

            for (uint256 i = 0; i < order.tokensOffered.length; ++i) {
                address token = order.tokensOffered[i];

                // Calculate incentives to give based on percentage of fill
                uint256 incentiveAmount = order.tokenAmountsOffered[token].mulWadDown(fillPercentage);
                params.amounts[i] = incentiveAmount;

                // Calculate fees to take based on percentage of fill
                uint256 protocolFeeAmount = order.tokenToProtocolFeeAmount[token].mulWadDown(fillPercentage);
                uint256 frontendFeeAmount = order.tokenToFrontendFeeAmount[token].mulWadDown(fillPercentage);

                // Take fees
                accountFee(protocolFeeClaimant, order.tokensOffered[i], protocolFeeAmount, order.ip);
                accountFee(frontendFeeRecipient, order.tokensOffered[i], frontendFeeAmount, order.ip);
            }

            // Set params for future payout
            weirollWalletToLockedRewardParams[address(wallet)] = params;
        } else {
            // Transfer the IP's incentives to the AP and set aside fees
            for (uint256 i = 0; i < order.tokensOffered.length; ++i) {
                address token = order.tokensOffered[i];

                // Calculate fees to take based on percentage of fill
                uint256 protocolFeeAmount = order.tokenToProtocolFeeAmount[token].mulWadDown(fillPercentage);
                uint256 frontendFeeAmount = order.tokenToFrontendFeeAmount[token].mulWadDown(fillPercentage);

                // Take fees
                accountFee(protocolFeeClaimant, order.tokensOffered[i], protocolFeeAmount, order.ip);
                accountFee(frontendFeeRecipient, order.tokensOffered[i], frontendFeeAmount, order.ip);

                // Calculate incentives to give based on percentage of fill
                uint256 incentiveAmount = order.tokenAmountsOffered[token].mulWadDown(fillPercentage);
                // Give incentives to AP immediately in an Upfront market
                if (PointsFactory(POINTS_FACTORY).isPointsProgram(token)) {
                    Points(token).award(msg.sender, incentiveAmount, order.ip);
                } else {
                    ERC20(token).safeTransfer(msg.sender, incentiveAmount);
                }
            }
        }

        if (fundingVault == address(0)) {
            // If the no fundingVault specified, fund the wallet directly from AP
            ERC20(market.inputToken).safeTransferFrom(msg.sender, address(wallet), fillAmount);
        } else {
            // Withdraw the tokens from the funding vault into the wallet
            ERC4626(fundingVault).withdraw(fillAmount, address(wallet), msg.sender);
        }

        // Execute deposit recipe
        wallet.executeWeiroll(market.depositRecipe.weirollCommands, market.depositRecipe.weirollState);

        emit IPOrderFilled(order.targetMarketID, orderID, order.ip, fillAmount, order.remainingQuantity, address(wallet));
    }

    /// @dev IP must approve all tokens to be spent (both fills + fees!) by the orderbook before calling this function
    function fillAPOrder(APOrder calldata order, uint256 fillAmount, address frontendFeeRecipient) public {
        if (order.expiry != 0 && block.timestamp > order.expiry) revert OrderExpired();

        bytes32 orderHash = getOrderHash(order);
        {
            // use a scoping block so solc knows `remaining` doesn't need to be kept around
            uint256 remaining = orderHashToRemainingQuantity[orderHash];
            if (fillAmount > remaining) {
                if (fillAmount != type(uint256).max) revert NotEnoughRemainingQuantity();
                fillAmount = remaining;
            }
        }

        if (fillAmount == 0) {
            revert CannotFillZeroQuantityOrder();
        }

        // Adjust remaining order quantity by amount filled
        orderHashToRemainingQuantity[orderHash] -= fillAmount;

        // Calculate percentage of AP oder that IP is fulfilling (IP gets this percantage of the order quantity in a Weiroll wallet specified by the market)
        uint256 fillPercentage = fillAmount.divWadDown(order.quantity);

        // Get Weiroll market
        WeirollMarket storage market = marketIDToWeirollMarket[order.targetMarketID];

        // Create weiroll wallet to lock assets for recipe execution(s)
        uint256 unlockTime = block.timestamp + market.lockupTime;
        bool forfeitable = market.rewardStyle == RewardStyle.Forfeitable;
        WeirollWallet wallet = WeirollWallet(
            payable(WEIROLL_WALLET_IMPLEMENTATION.clone(abi.encodePacked(order.ap, address(this), fillAmount, unlockTime, forfeitable, order.targetMarketID)))
        );

        if (market.rewardStyle != RewardStyle.Upfront) {
            // If RewardStyle is either Forfeitable or Arrear
            // Create locked rewards params to account for payouts upon wallet unlocking
            LockedRewardParams memory params;
            params.tokens = order.tokensRequested;
            params.amounts = new uint256[](order.tokensRequested.length);
            params.ip = msg.sender;

            for (uint256 i = 0; i < order.tokensRequested.length; ++i) {
                // This is the amount (per incentive) that the AP can claim once weiroll wallet is unlocked (fees are taken on top of this amount from the IP)
                params.amounts[i] = order.tokenAmountsRequested[i].mulWadDown(fillPercentage);

                // Calculate fees based on fill percentage. These fees will be taken on top of the AP's requested amount.
                uint256 protocolFeeAmount = params.amounts[i].mulWadDown(protocolFee);
                uint256 frontendFeeAmount = params.amounts[i].mulWadDown(market.frontendFee);

                // Account for protocol and frontend fees
                accountFee(protocolFeeClaimant, order.tokensRequested[i], protocolFeeAmount, msg.sender);
                accountFee(frontendFeeRecipient, order.tokensRequested[i], frontendFeeAmount, msg.sender);

                // If incentives will be paid out later, only handle the token case. Points will be awarded on claim.
                if (!PointsFactory(POINTS_FACTORY).isPointsProgram(order.tokensRequested[i])) {
                    // SafeTransferFrom does not check if a token address has any code, so we need to check it manually to prevent token deployment frontrunning
                    if (order.tokensRequested[i].code.length == 0) revert TokenDoesNotExist();
                    // If not a points program, transfer amount requested (based on fill percentage) to the orderbook in addition to protocol and frontend fees.
                    ERC20(order.tokensRequested[i]).safeTransferFrom(msg.sender, address(this), params.amounts[i] + protocolFeeAmount + frontendFeeAmount);
                }
            }
            // write locked params for use in claiming fees
            weirollWalletToLockedRewardParams[address(wallet)] = params;
        } else {
            // market.rewardStyle == RewardStyle.Upfront
            for (uint256 i = 0; i < order.tokensRequested.length; ++i) {
                // This is the amount that the AP can claim once weiroll wallet is unlocked (fees are taken on top of this amount from the IP)
                uint256 amount = order.tokenAmountsRequested[i].mulWadDown(fillPercentage);

                // Calculate fees based on fill percentage. These fees will be taken on top of the AP's requested amount.
                uint256 protocolFeeAmount = amount.mulWadDown(protocolFee);
                uint256 frontendFeeAmount = amount.mulWadDown(market.frontendFee);

                // Account for protocol and frontend fees
                accountFee(protocolFeeClaimant, order.tokensRequested[i], protocolFeeAmount, msg.sender);
                accountFee(frontendFeeRecipient, order.tokensRequested[i], frontendFeeAmount, msg.sender);

                // If incentives should be paid out upfront to AP
                if (PointsFactory(POINTS_FACTORY).isPointsProgram(order.tokensRequested[i])) {
                    // Award points right now if points program
                    Points(order.tokensRequested[i]).award(order.ap, amount, msg.sender);
                } else {
                    // Transfer protcol and frontend fees to orderbook for the claimants to withdraw them on-demand
                    ERC20(order.tokensRequested[i]).safeTransferFrom(msg.sender, address(this), protocolFeeAmount + frontendFeeAmount);
                    // Transfer AP's incentives to them on fill if token incentive
                    ERC20(order.tokensRequested[i]).safeTransferFrom(msg.sender, order.ap, amount);
                }
            }
        }

        if (order.fundingVault == address(0)) {
            // If the no fundingVault specified, fund the wallet directly from AP
            ERC20(market.inputToken).safeTransferFrom(order.ap, address(wallet), fillAmount);
        } else {
            // Withdraw the tokens from the funding vault into the wallet
            ERC4626(order.fundingVault).withdraw(fillAmount, address(wallet), order.ap);
        }

        // Execute deposit recipe
        wallet.executeWeiroll(market.depositRecipe.weirollCommands, market.depositRecipe.weirollState);

        emit APOrderFilled(order.targetMarketID, order.orderID, order.ap, fillAmount, orderHashToRemainingQuantity[orderHash], address(wallet));
    }

    /// @notice Cancel an AP order, setting the remaining quantity available to fill to 0
    function cancelAPOrder(APOrder calldata order) public {
        // Check that the cancelling party is the order's owner
        if (order.ap != msg.sender) revert NotOwner();

        // Check that the order doesn't have an indefinite expiry (cannot be cancelled)
        if (order.expiry == 0) revert OrderCannotExpire();

        // Check that the order isn't already filled, hasn't been cancelled already, or never existed
        bytes32 orderHash = getOrderHash(order);
        if (orderHashToRemainingQuantity[orderHash] == 0) revert NotEnoughRemainingQuantity();

        // Zero out the remaining quantity
        delete orderHashToRemainingQuantity[orderHash];

        emit APOrderCancelled(order.orderID);
    }

    /// @notice Cancel an IP order, setting the remaining quantity available to fill to 0 and returning the IP's incentives
    function cancelIPOrder(uint256 orderID) public {
        IPOrder storage order = orderIDToIPOrder[orderID];

        // Check that the cancelling party is the order's owner
        if (order.ip != msg.sender) revert NotOwner();

        // Check that the order doesn't have an indefinite expiry (cannot be cancelled)
        if (order.expiry == 0) revert OrderCannotExpire();

        // Check that the order isn't already filled, hasn't been cancelled already, or never existed
        if (order.remainingQuantity == 0) revert NotEnoughRemainingQuantity();

        // Check the percentage of the order not filled to calculate incentives to return
        uint256 percentNotFilled = order.remainingQuantity.divWadDown(order.quantity);

        // Transfer the remaining incentives back to the IP
        for (uint256 i = 0; i < order.tokensOffered.length; ++i) {
            address token = order.tokensOffered[i];
            if (!PointsFactory(POINTS_FACTORY).isPointsProgram(order.tokensOffered[i])) {
                // Calculate the incentives which are still available for takeback if its a token
                uint256 incentivesRemaining = order.tokenAmountsOffered[token].mulWadDown(percentNotFilled);

                // Calculate the unused fee amounts to reimburse to the IP
                uint256 unchargedFrontendFeeAmount = order.tokenToFrontendFeeAmount[token].mulWadDown(percentNotFilled);
                uint256 unchargedProtocolFeeAmount = order.tokenToProtocolFeeAmount[token].mulWadDown(percentNotFilled);

                // Transfer reimbursements to the IP
                ERC20(token).safeTransfer(order.ip, (incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeAmount));
            }

            /// Delete cancelled fields of dynamic arrays and mappings
            delete order.tokensOffered[i];
            delete order.tokenAmountsOffered[token];
            delete order.tokenToProtocolFeeAmount[token];
            delete order.tokenToFrontendFeeAmount[token];
        }

        // Delete unneeded order from mapping
        delete orderIDToIPOrder[orderID];

        emit IPOrderCancelled(orderID);
    }

    /// @notice For wallets of Forfeitable markets, an AP can call this function to forgo their rewards and unlock their wallet
    function forfeit(address weirollWallet) public isWeirollOwner(weirollWallet) nonReentrant {
        // Forfeit the locked rewards for the weirollWallet
        WeirollWallet(payable(weirollWallet)).forfeit();

        // Automatically execute the withdrawal script upon forfeiture
        _executeWithdrawalScript(weirollWallet);

        // Return the locked rewards to the IP
        LockedRewardParams storage params = weirollWalletToLockedRewardParams[weirollWallet];
        for (uint256 i = 0; i < params.tokens.length; ++i) {
            if (!PointsFactory(POINTS_FACTORY).isPointsProgram(params.tokens[i])) {
                uint256 amount = params.amounts[i];
                ERC20(params.tokens[i]).safeTransfer(params.ip, amount);
            }

            /// Delete fields of dynamic arrays and mappings
            delete params.tokens[i];
            delete params.amounts[i];
        }

        // zero out the mapping
        delete weirollWalletToLockedRewardParams[weirollWallet];
    }

    /// @notice Execute the withdrawal script in the weiroll wallet
    function executeWithdrawalScript(address weirollWallet) external isWeirollOwner(weirollWallet) weirollIsUnlocked(weirollWallet) nonReentrant {
        _executeWithdrawalScript(weirollWallet);
    }

    /// @param weirollWallet The wallet to claim for
    /// @param to The address to claim all rewards to
    function claim(address weirollWallet, address to) public isWeirollOwner(weirollWallet) weirollIsUnlocked(weirollWallet) nonReentrant {
        // Get locked reward details to facilitate claim
        LockedRewardParams storage params = weirollWalletToLockedRewardParams[weirollWallet];

        for (uint256 i = 0; i < params.tokens.length; ++i) {
            // Reward incentives to AP upon wallet unlock
            if (PointsFactory(POINTS_FACTORY).isPointsProgram(params.tokens[i])) {
                Points(params.tokens[i]).award(to, params.amounts[i], params.ip);
            } else {
                ERC20(params.tokens[i]).safeTransfer(to, params.amounts[i]);
            }

            /// Delete fields of dynamic arrays and mappings
            delete params.tokens[i];
            delete params.amounts[i];
        }

        // zero out the mapping
        delete weirollWalletToLockedRewardParams[weirollWallet];
    }

    /// @notice sets the protocol fee recipient, taken on all fills
    function setProtocolFeeClaimant(address _protocolFeeClaimant) public onlyOwner {
        protocolFeeClaimant = _protocolFeeClaimant;
    }

    /// @notice sets the protocol fee rate, taken on all fills
    /// @param _protocolFee The percent deducted from the IP's incentive amount and claimable by protocolFeeClaimant, 1e18 == 100% fee
    function setProtocolFee(uint256 _protocolFee) public onlyOwner {
        protocolFee = _protocolFee;
    }

    /// @notice sets the minimum frontend fee that a market can set and is paid to whoever fills the order
    function setMinimumFrontendFee(uint256 _minimumFrontendFee) public onlyOwner {
        minimumFrontendFee = _minimumFrontendFee;
    }

    /// @notice calculates the hash of an order
    function getOrderHash(APOrder memory order) public pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }

    /// @notice executes the withdrawal script for the provided weiroll wallet
    function _executeWithdrawalScript(address weirollWallet) internal {
        // Instantiate the WeirollWallet from the wallet address
        WeirollWallet wallet = WeirollWallet(payable(weirollWallet));

        // Get the marketID associated with the weiroll wallet
        uint256 weirollMarketId = wallet.marketId();

        // Get the market in order to get the withdrawal recipe
        WeirollMarket storage market = marketIDToWeirollMarket[weirollMarketId];

        //Execute the withdrawal recipe
        wallet.executeWeiroll(market.withdrawRecipe.weirollCommands, market.withdrawRecipe.weirollState);
    }

}
