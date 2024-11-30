// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { RecipeMarketHubBase, RewardStyle, WeirollWallet } from "src/base/RecipeMarketHubBase.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "lib/solady/src/utils/SafeCastLib.sol";
import { Points } from "src/Points.sol";
import { PointsFactory } from "src/PointsFactory.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";

import { GradualDutchAuction } from "src/gda/GDA.sol";

/// @title RecipeMarketHub
/// @author Jack Corddry, CopyPaste, Shivaansh Kapoor
/// @notice RecipeMarketHub contract for Incentivizing AP/IPs to participate in "recipe" markets which perform arbitrary actions
contract RecipeMarketHub is RecipeMarketHubBase {
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

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
        payable
        Owned(_owner)
    {
        WEIROLL_WALLET_IMPLEMENTATION = _weirollWalletImplementation;
        POINTS_FACTORY = _pointsFactory;
        protocolFee = _protocolFee;
        protocolFeeClaimant = _owner;
        minimumFrontendFee = _minimumFrontendFee;
    }

    /// @notice Create a new recipe market
    /// @param inputToken The token that will be deposited into the user's weiroll wallet for use in the recipe
    /// @param lockupTime The time in seconds that the user's weiroll wallet will be locked up for after deposit
    /// @param frontendFee The fee that the frontend will take from the user's weiroll wallet, 1e18 == 100% fee
    /// @param depositRecipe The weiroll script that will be executed after the inputToken is transferred to the wallet
    /// @param withdrawRecipe The weiroll script that may be executed after lockupTime has passed to unwind a user's position
    /// @custom:field rewardStyle Whether the rewards are paid at the beginning, locked until the end, or forfeitable until the end
    /// @return marketHash The hash of the newly created market
    function createMarket(
        address inputToken,
        uint256 lockupTime,
        uint256 frontendFee,
        Recipe calldata depositRecipe,
        Recipe calldata withdrawRecipe,
        RewardStyle rewardStyle
    )
        external
        payable
        returns (bytes32 marketHash)
    {
        // Check that the input token is not the zero address
        if (inputToken == address(0)) {
            revert InvalidMarketInputToken();
        }
        // Check that the frontend fee is at least the global minimum
        if (frontendFee < minimumFrontendFee) {
            revert FrontendFeeTooLow();
        }
        // Check that the sum of fees isn't too high
        if ((frontendFee + protocolFee) > 1e18) {
            revert TotalFeeTooHigh();
        }

        WeirollMarket memory market = WeirollMarket(numMarkets, ERC20(inputToken), lockupTime, frontendFee, depositRecipe, withdrawRecipe, rewardStyle);
        marketHash = getMarketHash(market);
        marketHashToWeirollMarket[marketHash] = market;

        emit MarketCreated(numMarkets, marketHash, inputToken, lockupTime, frontendFee, rewardStyle);

        numMarkets++;
    }

    /// @notice Create a new AP offer. Offer params will be emitted in an event while only the hash of the offer and offer quantity is stored onchain
    /// @dev AP offers are funded via approvals to ensure multiple offers can be placed off of a single input
    /// @dev Setting an expiry of 0 means the offer never expires
    /// @param targetMarketHash The hash of the weiroll market to create the AP offer for
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from, if set to 0, the AP will deposit the base asset directly
    /// @param quantity The total amount of input tokens to be deposited
    /// @param expiry The timestamp after which the offer is considered expired
    /// @param incentivesRequested The addresses of the incentives requested by the AP to satisfy the offer
    /// @param incentiveAmountsRequested The amount of each incentive requested by the AP to satisfy the offer
    /// @return offerHash The hash of the AP offer created
    function createAPOffer(
        bytes32 targetMarketHash,
        address fundingVault,
        uint256 quantity,
        uint256 expiry,
        address[] calldata incentivesRequested,
        uint256[] calldata incentiveAmountsRequested
    )
        external
        payable
        returns (bytes32 offerHash)
    {
        // Retrieve the target market
        WeirollMarket storage targetMarket = marketHashToWeirollMarket[targetMarketHash];

        // Check that the market exists
        if (address(targetMarket.inputToken) == address(0)) {
            revert MarketDoesNotExist();
        }
        // Check offer isn't expired (expiries of 0 live forever)
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOffer();
        }
        // Check offer isn't empty
        if (quantity < MINIMUM_QUANTITY) {
            revert CannotPlaceZeroQuantityOffer();
        }
        // Check incentive and amounts arrays are the same length
        if (incentivesRequested.length != incentiveAmountsRequested.length) {
            revert ArrayLengthMismatch();
        }
        address lastIncentive;
        for (uint256 i; i < incentivesRequested.length; i++) {
            address incentive = incentivesRequested[i];
            if (uint256(bytes32(bytes20(incentive))) <= uint256(bytes32(bytes20(lastIncentive)))) {
                revert OfferCannotContainDuplicates();
            }
            lastIncentive = incentive;
        }

        // NOTE: The cool use of short-circuit means this call can't revert if fundingVault doesn't support asset()
        if (fundingVault != address(0) && targetMarket.inputToken != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }

        // Map the offer hash to the offer quantity
        APOffer memory offer =
            APOffer(numAPOffers, targetMarketHash, msg.sender, fundingVault, quantity, expiry, incentivesRequested, incentiveAmountsRequested);
        offerHash = getAPOfferHash(offer);
        offerHashToRemainingQuantity[offerHash] = quantity;

        /// @dev APOffer events are stored in events and do not exist onchain outside of the offerHashToRemainingQuantity mapping
        emit APOfferCreated(numAPOffers, targetMarketHash, fundingVault, quantity, incentivesRequested, incentiveAmountsRequested, expiry);

        // Increment the number of AP offers created
        numAPOffers++;
    }

    /// @notice Create a new IP offer, transferring the IP's incentives to the RecipeMarketHub and putting all the offer params in contract storage
    /// @dev IP must approve all incentives to be spent by the RecipeMarketHub before calling this function
    /// @param targetMarketHash The hash of the weiroll market to create the IP offer for
    /// @param quantity The total amount of input tokens to be deposited
    /// @param expiry The timestamp after which the offer is considered expired
    /// @param incentivesOffered The addresses of the incentives offered by the IP
    /// @param incentiveAmountsPaid The amount of each incentives paid by the IP (including fees)
    /// @return offerHash The hash of the IP offer created
    function createIPOffer(
        bytes32 targetMarketHash,
        uint256 quantity,
        uint256 expiry,
        address[] calldata incentivesOffered,
        uint256[] calldata incentiveAmountsPaid
    )
        external
        payable
        nonReentrant
        returns (bytes32 offerHash)
    {
        // Retrieve the target market
        WeirollMarket storage targetMarket = marketHashToWeirollMarket[targetMarketHash];

        // Check that the market exists
        if (address(targetMarket.inputToken) == address(0)) {
            revert MarketDoesNotExist();
        }
        // Check that the offer isn't expired
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOffer();
        }

        // Check that the incentives and amounts arrays are the same length
        if (incentivesOffered.length != incentiveAmountsPaid.length) {
            revert ArrayLengthMismatch();
        }

        // Check offer isn't empty
        if (quantity < MINIMUM_QUANTITY) {
            revert CannotPlaceZeroQuantityOffer();
        }

        // To keep track of incentives allocated to the AP and fees (per incentive)
        uint256[] memory incentiveAmountsOffered = new uint256[](incentivesOffered.length);
        uint256[] memory protocolFeesToBePaid = new uint256[](incentivesOffered.length);
        uint256[] memory frontendFeesToBePaid = new uint256[](incentivesOffered.length);

        // Transfer the IP's incentives to the RecipeMarketHub and set aside fees
        address lastIncentive;
        for (uint256 i = 0; i < incentivesOffered.length; ++i) {
            // Get the incentive offered
            address incentive = incentivesOffered[i];

            // Check that the sorted incentive array has no duplicates
            if (uint256(bytes32(bytes20(incentive))) <= uint256(bytes32(bytes20(lastIncentive)))) {
                revert OfferCannotContainDuplicates();
            }
            lastIncentive = incentive;

            // Total amount IP is paying in this incentive including fees
            uint256 amount = incentiveAmountsPaid[i];

            // Get the frontend fee for the target weiroll market
            uint256 frontendFee = targetMarket.frontendFee;

            // Calculate incentive and fee breakdown
            uint256 incentiveAmount = amount.divWadDown(1e18 + protocolFee + frontendFee);
            uint256 protocolFeeAmount = incentiveAmount.mulWadDown(protocolFee);
            uint256 frontendFeeAmount = incentiveAmount.mulWadDown(frontendFee);

            // Use a scoping block to avoid stack to deep errors
            {
                // Track incentive amounts and fees (per incentive)
                incentiveAmountsOffered[i] = incentiveAmount;
                protocolFeesToBePaid[i] = protocolFeeAmount;
                frontendFeesToBePaid[i] = frontendFeeAmount;
            }

            // Check if incentive is a points program
            if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
                // If points incentive, make sure:
                // 1. The points factory used to create the program is the same as this RecipeMarketHubs PF
                // 2. IP placing the offer can award points
                // 3. Points factory has this RecipeMarketHub marked as a valid RO - can be assumed true
                if (POINTS_FACTORY != address(Points(incentive).pointsFactory()) || !Points(incentive).allowedIPs(msg.sender)) {
                    revert InvalidPointsProgram();
                }
            } else {
                // SafeTransferFrom does not check if a incentive address has any code, so we need to check it manually to prevent incentive deployment
                // frontrunning
                if (incentive.code.length == 0) revert TokenDoesNotExist();
                // Transfer frontend fee + protocol fee + incentiveAmount of the incentive to RecipeMarketHub
                ERC20(incentive).safeTransferFrom(msg.sender, address(this), incentiveAmount + protocolFeeAmount + frontendFeeAmount);
            }
        }

        // Set the offer hash
        offerHash = getIPOfferHash(numIPOffers, targetMarketHash, msg.sender, expiry, quantity, incentivesOffered, incentiveAmountsOffered);
        // Create and store the offer
        IPOffer storage offer = offerHashToIPOffer[offerHash];
        offer.offerID = numIPOffers;
        offer.targetMarketHash = targetMarketHash;
        offer.ip = msg.sender;
        offer.quantity = quantity;
        offer.remainingQuantity = quantity;
        offer.expiry = expiry;
        offer.incentivesOffered = incentivesOffered;

        // Set incentives and fees in the offer mapping
        for (uint256 i = 0; i < incentivesOffered.length; ++i) {
            address incentive = incentivesOffered[i];

            offer.incentiveAmountsOffered[incentive] = incentiveAmountsOffered[i];
            offer.incentiveToProtocolFeeAmount[incentive] = protocolFeesToBePaid[i];
            offer.incentiveToFrontendFeeAmount[incentive] = frontendFeesToBePaid[i];
        }

        // Emit IP offer creation event
        emit IPOfferCreated(
            numIPOffers, offerHash, targetMarketHash, quantity, incentivesOffered, incentiveAmountsOffered, protocolFeesToBePaid, frontendFeesToBePaid, expiry
        );

        // Increment the number of IP offers created
        numIPOffers++;
    }

    /// @notice Create a new IP offer, transferring the IP's incentives to the RecipeMarketHub and putting all the offer params in contract storage
    /// @dev IP must approve all incentives to be spent by the RecipeMarketHub before calling this function
    /// @param targetMarketHash The hash of the weiroll market to create the IP offer for
    /// @param quantity The total amount of input tokens to be deposited
    /// @param expiry The timestamp after which the offer is considered expired
    /// @param incentivesOffered The addresses of the incentives offered by the IP
    /// @param incentiveAmountsPaid The amount of each incentives paid by the IP (including fees)
    /// @param gdaParams gradual dutch auction params
    /// @return offerHash The hash of the IP offer created
    function createIPGdaOffer(
        bytes32 targetMarketHash,
        uint256 quantity,
        uint256 expiry,
        address[] calldata incentivesOffered,
        uint256[] calldata incentiveAmountsPaid,
        GDAParams calldata gdaParams
    )
        external
        payable
        nonReentrant
        returns (bytes32 offerHash)
    {
        // Retrieve the target market
        WeirollMarket storage targetMarket = marketHashToWeirollMarket[targetMarketHash];

        // Check that the market exists
        if (address(targetMarket.inputToken) == address(0)) {
            revert MarketDoesNotExist();
        }
        // Check that the offer isn't expired
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOffer();
        }

        // Check that the incentives and amounts arrays are the same length
        if (incentivesOffered.length != incentiveAmountsPaid.length) {
            revert ArrayLengthMismatch();
        }

        // Check offer isn't empty
        if (quantity < MINIMUM_QUANTITY) {
            revert CannotPlaceZeroQuantityOffer();
        }

        if (gdaParams.initialDiscountMultiplier >= 1e18) {
            revert InvalidInitialDiscountMultiplier();
        }

        // To keep track of incentives allocated to the AP and fees (per incentive)
        uint256[] memory incentiveAmountsOffered = new uint256[](incentivesOffered.length);
        uint256[] memory protocolFeesToBePaid = new uint256[](incentivesOffered.length);
        uint256[] memory frontendFeesToBePaid = new uint256[](incentivesOffered.length);

        // Transfer the IP's incentives to the RecipeMarketHub and set aside fees
        address lastIncentive;
        for (uint256 i = 0; i < incentivesOffered.length; ++i) {
            // Get the incentive offered
            address incentive = incentivesOffered[i];

            // Check that the sorted incentive array has no duplicates
            if (uint256(bytes32(bytes20(incentive))) <= uint256(bytes32(bytes20(lastIncentive)))) {
                revert OfferCannotContainDuplicates();
            }
            lastIncentive = incentive;

            // Total amount IP is paying in this incentive including fees
            uint256 amount = incentiveAmountsPaid[i];

            // Get the frontend fee for the target weiroll market
            uint256 frontendFee = targetMarket.frontendFee;

            // Calculate incentive and fee breakdown
            uint256 incentiveAmount = amount.divWadDown(1e18 + protocolFee + frontendFee);
            uint256 protocolFeeAmount = incentiveAmount.mulWadDown(protocolFee);
            uint256 frontendFeeAmount = incentiveAmount.mulWadDown(frontendFee);

            // Use a scoping block to avoid stack to deep errors
            {
                // Track incentive amounts and fees (per incentive)
                incentiveAmountsOffered[i] = incentiveAmount;
                protocolFeesToBePaid[i] = protocolFeeAmount;
                frontendFeesToBePaid[i] = frontendFeeAmount;
            }

            // Check if incentive is a points program
            if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
                // If points incentive, make sure:
                // 1. The points factory used to create the program is the same as this RecipeMarketHubs PF
                // 2. IP placing the offer can award points
                // 3. Points factory has this RecipeMarketHub marked as a valid RO - can be assumed true
                if (POINTS_FACTORY != address(Points(incentive).pointsFactory()) || !Points(incentive).allowedIPs(msg.sender)) {
                    revert InvalidPointsProgram();
                }
            } else {
                // SafeTransferFrom does not check if a incentive address has any code, so we need to check it manually to prevent incentive deployment
                // frontrunning
                if (incentive.code.length == 0) revert TokenDoesNotExist();
                // Transfer frontend fee + protocol fee + incentiveAmount of the incentive to RecipeMarketHub
                ERC20(incentive).safeTransferFrom(msg.sender, address(this), incentiveAmount + protocolFeeAmount + frontendFeeAmount);
            }
        }

        // Set the offer hash
        offerHash = getIPGdaOfferHash(numIPOffers, targetMarketHash, msg.sender, expiry, quantity, incentivesOffered, incentiveAmountsOffered, gdaParams);
        // Create and store the offer
        IPGdaOffer storage offer = offerHashToIPGdaOffer[offerHash];
        offer.offerID = numIPOffers;
        offer.targetMarketHash = targetMarketHash;
        offer.ip = msg.sender;
        offer.quantity = quantity;
        offer.remainingQuantity = quantity;
        offer.expiry = expiry;
        offer.incentivesOffered = incentivesOffered;
        offer.gdaParams.decayRate = gdaParams.decayRate;
        offer.gdaParams.emissionRate = gdaParams.emissionRate;
        offer.gdaParams.lastAuctionStartTime = SafeCastLib.toInt256(block.timestamp);
        offer.gdaParams.initialDiscountMultiplier = gdaParams.initialDiscountMultiplier;

        // Set incentives and fees in the offer mapping
        for (uint256 i = 0; i < incentivesOffered.length; ++i) {
            address incentive = incentivesOffered[i];
            offer.incentiveAmountsOffered[incentive] = incentiveAmountsOffered[i];
            offer.initialIncentiveAmountsOffered[incentive] = incentiveAmountsOffered[i] * offer.gdaParams.initialDiscountMultiplier / 1e18;
            offer.incentiveToProtocolFeeAmount[incentive] = protocolFeesToBePaid[i];
            offer.incentiveToFrontendFeeAmount[incentive] = frontendFeesToBePaid[i];
        }

        // Emit IP offer creation event
        emit IPGdaOfferCreated(
            numIPOffers,
            offerHash,
            targetMarketHash,
            quantity,
            incentivesOffered,
            incentiveAmountsOffered,
            protocolFeesToBePaid,
            frontendFeesToBePaid,
            expiry,
            offer.gdaParams
        );

        // Increment the number of IP offers created
        numIPGdaOffers++;
    }

    /// @param incentiveToken The incentive token to claim fees for
    /// @param to The address to send fees claimed to
    function claimFees(address incentiveToken, address to) external payable {
        uint256 amount = feeClaimantToTokenToAmount[msg.sender][incentiveToken];
        delete feeClaimantToTokenToAmount[msg.sender][incentiveToken];
        ERC20(incentiveToken).safeTransfer(to, amount);
        emit FeesClaimed(msg.sender, incentiveToken, amount);
    }

    /// @notice Filling multiple IP offers
    /// @param ipOfferHashes The hashes of the IP offers to fill
    /// @param fillAmounts The amounts of input tokens to fill the corresponding offers with
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from (vault not used if set to address(0))
    /// @param frontendFeeRecipient The address that will receive the frontend fee
    function fillIPOffers(
        bytes32[] calldata ipOfferHashes,
        uint256[] calldata fillAmounts,
        address fundingVault,
        address frontendFeeRecipient
    )
        external
        payable
        nonReentrant
        offersNotPaused
    {
        if (ipOfferHashes.length != fillAmounts.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < ipOfferHashes.length; ++i) {
            _fillIPOffer(ipOfferHashes[i], fillAmounts[i], fundingVault, frontendFeeRecipient);
        }
    }

    /// @notice Fill an IP offer, transferring the IP's incentives to the AP, withdrawing the AP from their funding vault into a fresh weiroll wallet, and
    /// executing the weiroll recipe
    /// @param offerHash The hash of the IP offer to fill
    /// @param fillAmount The amount of input tokens to fill the offer with
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from (vault not used if set to address(0))
    /// @param frontendFeeRecipient The address that will receive the frontend fee
    function _fillIPOffer(bytes32 offerHash, uint256 fillAmount, address fundingVault, address frontendFeeRecipient) internal {
        // Retreive the IPOffer and WeirollMarket structs
        IPOffer storage offer = offerHashToIPOffer[offerHash];
        WeirollMarket storage market = marketHashToWeirollMarket[offer.targetMarketHash];

        // Check that the offer isn't expired
        if (offer.expiry != 0 && block.timestamp > offer.expiry) {
            revert OfferExpired();
        }
        // Check that the offer has enough remaining quantity
        if (offer.remainingQuantity < fillAmount && fillAmount != type(uint256).max) {
            revert NotEnoughRemainingQuantity();
        }
        if (fillAmount == type(uint256).max) {
            fillAmount = offer.remainingQuantity;
        }
        // Check that the offer's base asset matches the market's base asset
        if (fundingVault != address(0) && market.inputToken != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }
        // Check that the offer isn't empty
        if (fillAmount == 0) {
            revert CannotPlaceZeroQuantityOffer();
        }

        // Update the offer's remaining quantity before interacting with external contracts
        offer.remainingQuantity -= fillAmount;

        WeirollWallet wallet;
        {
            // Use a scoping block to avoid stack too deep
            bool forfeitable = market.rewardStyle == RewardStyle.Forfeitable;
            uint256 unlockTime = block.timestamp + market.lockupTime;

            // Create weiroll wallet to lock assets for recipe execution(s)
            wallet = WeirollWallet(
                payable(
                    WEIROLL_WALLET_IMPLEMENTATION.clone(
                        abi.encodePacked(msg.sender, address(this), fillAmount, unlockTime, forfeitable, offer.targetMarketHash)
                    )
                )
            );
        }

        // Number of incentives offered by the IP
        uint256 numIncentives = offer.incentivesOffered.length;

        // Arrays to store incentives and fee amounts to be paid
        uint256[] memory incentiveAmountsPaid = new uint256[](numIncentives);
        uint256[] memory protocolFeesPaid = new uint256[](numIncentives);
        uint256[] memory frontendFeesPaid = new uint256[](numIncentives);

        // Calculate the percentage of the offer the AP is filling
        uint256 fillPercentage = fillAmount.divWadDown(offer.quantity);

        // Perform incentive accounting on a per incentive basis
        for (uint256 i = 0; i < numIncentives; ++i) {
            // Incentive address
            address incentive = offer.incentivesOffered[i];

            // Calculate fees to take based on percentage of fill
            protocolFeesPaid[i] = offer.incentiveToProtocolFeeAmount[incentive].mulWadDown(fillPercentage);
            frontendFeesPaid[i] = offer.incentiveToFrontendFeeAmount[incentive].mulWadDown(fillPercentage);

            // Calculate incentives to give based on percentage of fill
            incentiveAmountsPaid[i] = offer.incentiveAmountsOffered[incentive].mulWadDown(fillPercentage);

            if (market.rewardStyle == RewardStyle.Upfront) {
                // Push incentives to AP and account fees on fill in an upfront market
                _pushIncentivesAndAccountFees(
                    incentive, msg.sender, incentiveAmountsPaid[i], protocolFeesPaid[i], frontendFeesPaid[i], offer.ip, frontendFeeRecipient
                );
            }
        }

        if (market.rewardStyle != RewardStyle.Upfront) {
            // If RewardStyle is either Forfeitable or Arrear
            // Create locked rewards params to account for payouts upon wallet unlocking
            LockedRewardParams storage params = weirollWalletToLockedIncentivesParams[address(wallet)];
            params.incentives = offer.incentivesOffered;
            params.amounts = incentiveAmountsPaid;
            params.ip = offer.ip;
            params.frontendFeeRecipient = frontendFeeRecipient;
            params.wasIPOffer = true;
            params.offerHash = offerHash;
        }

        // Fund the weiroll wallet with the specified amount of the market's input token
        // Will use the funding vault if specified or will fund directly from the AP
        _fundWeirollWallet(fundingVault, msg.sender, market.inputToken, fillAmount, address(wallet));

        // Execute deposit recipe
        wallet.executeWeiroll(market.depositRecipe.weirollCommands, market.depositRecipe.weirollState);

        emit IPOfferFilled(offerHash, fillAmount, address(wallet), incentiveAmountsPaid, protocolFeesPaid, frontendFeesPaid);
    }

    /// @notice Fill an IP Gda offer, transferring the IP's incentives to the AP, withdrawing the AP from their funding vault into a fresh weiroll wallet, and
    /// executing the weiroll recipe
    function _fillIPGdaOffer(bytes32 offerHash, uint256 fillAmount, address fundingVault, address frontendFeeRecipient) internal {
        // Retreive the IPOffer and WeirollMarket structs
        IPGdaOffer storage offer = offerHashToIPGdaOffer[offerHash];
        // IPOffer storage offer = offerHashToIPOffer[offerHash];
        WeirollMarket storage market = marketHashToWeirollMarket[offer.targetMarketHash];

        // Check that the offer isn't expired
        if (offer.expiry != 0 && block.timestamp > offer.expiry) {
            revert OfferExpired();
        }
        // Check that the offer has enough remaining quantity
        if (offer.remainingQuantity < fillAmount && fillAmount != type(uint256).max) {
            revert NotEnoughRemainingQuantity();
        }
        if (fillAmount == type(uint256).max) {
            fillAmount = offer.remainingQuantity;
        }
        // Check that the offer's base asset matches the market's base asset
        if (fundingVault != address(0) && market.inputToken != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }
        // Check that the offer isn't empty
        if (fillAmount == 0) {
            revert CannotPlaceZeroQuantityOffer();
        }

        uint256 incentiveMultiplier = GradualDutchAuction._calculateIncentiveMultiplier(
            offer.gdaParams.decayRate, offer.gdaParams.emissionRate, offer.gdaParams.lastAuctionStartTime, fillAmount
        );

        offer.gdaParams.lastAuctionStartTime = SafeCastLib.toInt256(block.timestamp);

        // Update the offer's remaining quantity before interacting with external contracts
        offer.remainingQuantity -= fillAmount;

        WeirollWallet wallet;
        {
            // Use a scoping block to avoid stack too deep
            bool forfeitable = market.rewardStyle == RewardStyle.Forfeitable;
            uint256 unlockTime = block.timestamp + market.lockupTime;

            // Create weiroll wallet to lock assets for recipe execution(s)
            wallet = WeirollWallet(
                payable(
                    WEIROLL_WALLET_IMPLEMENTATION.clone(
                        abi.encodePacked(msg.sender, address(this), fillAmount, unlockTime, forfeitable, offer.targetMarketHash)
                    )
                )
            );
        }

        // Number of incentives offered by the IP
        uint256 numIncentives = offer.incentivesOffered.length;

        // Arrays to store incentives and fee amounts to be paid
        uint256[] memory incentiveAmountsPaid = new uint256[](numIncentives);
        uint256[] memory protocolFeesPaid = new uint256[](numIncentives);
        uint256[] memory frontendFeesPaid = new uint256[](numIncentives);

        // Calculate the percentage of the offer the AP is filling
        uint256 fillPercentage = fillAmount.divWadDown(offer.quantity);

        // Perform incentive accounting on a per incentive basis
        for (uint256 i = 0; i < numIncentives; ++i) {
            // Incentive address
            address incentive = offer.incentivesOffered[i];

            // Calculate fees to take based on percentage of fill
            protocolFeesPaid[i] = offer.incentiveToProtocolFeeAmount[incentive].mulWadDown(fillPercentage);
            frontendFeesPaid[i] = offer.incentiveToFrontendFeeAmount[incentive].mulWadDown(fillPercentage);

            // Calculate incentives to give based on percentage of fill
            incentiveAmountsPaid[i] = offer.initialIncentiveAmountsOffered[incentive].mulWadDown(incentiveMultiplier).mulWadDown(fillPercentage);

            if (market.rewardStyle == RewardStyle.Upfront) {
                // Push incentives to AP and account fees on fill in an upfront market
                _pushIncentivesAndAccountFees(
                    incentive, msg.sender, incentiveAmountsPaid[i], protocolFeesPaid[i], frontendFeesPaid[i], offer.ip, frontendFeeRecipient
                );
            }
        }

        if (market.rewardStyle != RewardStyle.Upfront) {
            // If RewardStyle is either Forfeitable or Arrear
            // Create locked rewards params to account for payouts upon wallet unlocking
            LockedRewardParams storage params = weirollWalletToLockedIncentivesParams[address(wallet)];
            params.incentives = offer.incentivesOffered;
            params.amounts = incentiveAmountsPaid;
            params.ip = offer.ip;
            params.frontendFeeRecipient = frontendFeeRecipient;
            params.wasIPOffer = true;
            params.offerHash = offerHash;
        }

        // Fund the weiroll wallet with the specified amount of the market's input token
        // Will use the funding vault if specified or will fund directly from the AP
        _fundWeirollWallet(fundingVault, msg.sender, market.inputToken, fillAmount, address(wallet));

        // Execute deposit recipe
        wallet.executeWeiroll(market.depositRecipe.weirollCommands, market.depositRecipe.weirollState);

        emit IPGdaOfferFilled(offerHash, fillAmount, address(wallet), incentiveAmountsPaid, protocolFeesPaid, frontendFeesPaid);
    }

    /// @dev Fill multiple AP offers
    /// @param offers The AP offers to fill
    /// @param fillAmounts The amount of input tokens to fill the corresponding offer with
    /// @param frontendFeeRecipient The address that will receive the frontend fee
    function fillAPOffers(
        APOffer[] calldata offers,
        uint256[] calldata fillAmounts,
        address frontendFeeRecipient
    )
        external
        payable
        nonReentrant
        offersNotPaused
    {
        if (offers.length != fillAmounts.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < offers.length; ++i) {
            _fillAPOffer(offers[i], fillAmounts[i], frontendFeeRecipient);
        }
    }

    /// @dev Fill an AP offer
    /// @dev IP must approve all incentives to be spent (both fills + fees!) by the RecipeMarketHub before calling this function.
    /// @param offer The AP offer to fill
    /// @param fillAmount The amount of input tokens to fill the offer with
    /// @param frontendFeeRecipient The address that will receive the frontend fee
    function _fillAPOffer(APOffer calldata offer, uint256 fillAmount, address frontendFeeRecipient) internal {
        if (offer.expiry != 0 && block.timestamp > offer.expiry) {
            revert OfferExpired();
        }

        bytes32 offerHash = getAPOfferHash(offer);

        uint256 remaining = offerHashToRemainingQuantity[offerHash];
        if (fillAmount > remaining) {
            if (fillAmount != type(uint256).max) {
                revert NotEnoughRemainingQuantity();
            }
            fillAmount = remaining;
        }

        if (fillAmount == 0) {
            revert CannotFillZeroQuantityOffer();
        }

        // Adjust remaining offer quantity by amount filled
        offerHashToRemainingQuantity[offerHash] -= fillAmount;

        // Calculate percentage of AP oder that IP is filling (IP gets this percantage of the offer quantity in a Weiroll wallet specified by the market)
        uint256 fillPercentage = fillAmount.divWadDown(offer.quantity);

        if (fillPercentage < MIN_FILL_PERCENT && fillAmount != remaining) revert InsufficientFillPercent();

        // Get Weiroll market
        WeirollMarket storage market = marketHashToWeirollMarket[offer.targetMarketHash];

        WeirollWallet wallet;
        {
            // Create weiroll wallet to lock assets for recipe execution(s)
            uint256 unlockTime = block.timestamp + market.lockupTime;
            bool forfeitable = market.rewardStyle == RewardStyle.Forfeitable;
            wallet = WeirollWallet(
                payable(
                    WEIROLL_WALLET_IMPLEMENTATION.clone(abi.encodePacked(offer.ap, address(this), fillAmount, unlockTime, forfeitable, offer.targetMarketHash))
                )
            );
        }

        // Number of incentives requested by the AP
        uint256 numIncentives = offer.incentivesRequested.length;

        // Arrays to store incentives and fee amounts to be paid
        uint256[] memory incentiveAmountsPaid = new uint256[](numIncentives);
        uint256[] memory protocolFeesPaid = new uint256[](numIncentives);
        uint256[] memory frontendFeesPaid = new uint256[](numIncentives);

        // Fees at the time of fill
        uint256 protocolFeeAtFill = protocolFee;
        uint256 marketFrontendFee = market.frontendFee;

        for (uint256 i = 0; i < numIncentives; ++i) {
            // Incentive requested by AP
            address incentive = offer.incentivesRequested[i];

            // This is the incentive amount allocated to the AP
            uint256 incentiveAmount = offer.incentiveAmountsRequested[i].mulWadDown(fillPercentage);
            // Check that the incentives allocated to the AP are non-zero
            if (incentiveAmount == 0) {
                revert NoIncentivesPaidOnFill();
            }
            incentiveAmountsPaid[i] = incentiveAmount;

            // Calculate fees based on fill percentage. These fees will be taken on top of the AP's requested amount.
            protocolFeesPaid[i] = incentiveAmount.mulWadDown(protocolFeeAtFill);
            frontendFeesPaid[i] = incentiveAmount.mulWadDown(marketFrontendFee);

            // Pull incentives from IP and account fees
            _pullIncentivesOnAPFill(incentive, incentiveAmount, protocolFeesPaid[i], frontendFeesPaid[i], offer.ap, frontendFeeRecipient, market.rewardStyle);
        }

        if (market.rewardStyle != RewardStyle.Upfront) {
            // If RewardStyle is either Forfeitable or Arrear
            // Create locked rewards params to account for payouts upon wallet unlocking
            LockedRewardParams storage params = weirollWalletToLockedIncentivesParams[address(wallet)];
            params.incentives = offer.incentivesRequested;
            params.amounts = incentiveAmountsPaid;
            params.ip = msg.sender;
            params.frontendFeeRecipient = frontendFeeRecipient;
            params.protocolFeeAtFill = protocolFeeAtFill;
            // Redundant: Make sure this is set to false in case of a forfeit
            delete params.wasIPOffer;
        }

        // Fund the weiroll wallet with the specified amount of the market's input token
        // Will use the funding vault if specified or will fund directly from the AP
        _fundWeirollWallet(offer.fundingVault, offer.ap, market.inputToken, fillAmount, address(wallet));

        // Execute deposit recipe
        wallet.executeWeiroll(market.depositRecipe.weirollCommands, market.depositRecipe.weirollState);

        emit APOfferFilled(offer.offerID, fillAmount, address(wallet), incentiveAmountsPaid, protocolFeesPaid, frontendFeesPaid);
    }

    /// @notice Cancel an AP offer, setting the remaining quantity available to fill to 0
    function cancelAPOffer(APOffer calldata offer) external payable {
        // Check that the cancelling party is the offer's owner
        if (offer.ap != msg.sender) revert NotOwner();

        // Check that the offer isn't already filled, hasn't been cancelled already, or never existed
        bytes32 offerHash = getAPOfferHash(offer);
        if (offerHashToRemainingQuantity[offerHash] == 0) {
            revert NotEnoughRemainingQuantity();
        }

        // Set remaining quantity to 0 - effectively cancelling the offer
        delete offerHashToRemainingQuantity[offerHash];

        emit APOfferCancelled(offer.offerID);
    }

    /// @notice Cancel an IP offer, setting the remaining quantity available to fill to 0 and returning the IP's incentives
    function cancelIPOffer(bytes32 offerHash) external payable nonReentrant {
        IPOffer storage offer = offerHashToIPOffer[offerHash];

        // Check that the cancelling party is the offer's owner
        if (offer.ip != msg.sender) revert NotOwner();

        // Check that the offer isn't already filled, hasn't been cancelled already, or never existed
        if (offer.remainingQuantity == 0) revert NotEnoughRemainingQuantity();

        RewardStyle marketRewardStyle = marketHashToWeirollMarket[offer.targetMarketHash].rewardStyle;
        // Check the percentage of the offer not filled to calculate incentives to return
        uint256 percentNotFilled = offer.remainingQuantity.divWadDown(offer.quantity);

        // Transfer the remaining incentives back to the IP
        for (uint256 i = 0; i < offer.incentivesOffered.length; ++i) {
            address incentive = offer.incentivesOffered[i];
            if (!PointsFactory(POINTS_FACTORY).isPointsProgram(offer.incentivesOffered[i])) {
                // Calculate the incentives which are still available for refunding the IP
                uint256 incentivesRemaining = offer.incentiveAmountsOffered[incentive].mulWadDown(percentNotFilled);

                // Calculate the unused fee amounts to refunding to the IP
                uint256 unchargedFrontendFeeAmount = offer.incentiveToFrontendFeeAmount[incentive].mulWadDown(percentNotFilled);
                uint256 unchargedProtocolFeeAmount = offer.incentiveToProtocolFeeAmount[incentive].mulWadDown(percentNotFilled);

                // Transfer reimbursements to the IP
                ERC20(incentive).safeTransfer(offer.ip, (incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeAmount));
            }

            /// Delete cancelled fields of dynamic arrays and mappings
            delete offer.incentivesOffered[i];
            delete offer.incentiveAmountsOffered[incentive];

            if (marketRewardStyle == RewardStyle.Upfront) {
                // Need these on forfeit and claim for forfeitable and arrear markets
                // Safe to delete for Upfront markets
                delete offer.incentiveToProtocolFeeAmount[incentive];
                delete offer.incentiveToFrontendFeeAmount[incentive];
            }
        }

        if (marketRewardStyle != RewardStyle.Upfront) {
            // Need quantity to take the fees on forfeit and claim - don't delete
            // Need expiry to check offer expiry status on forfeit - don't delete
            // Delete the rest of the fields to indicate the offer was cancelled on forfeit
            delete offerHashToIPOffer[offerHash].targetMarketHash;
            delete offerHashToIPOffer[offerHash].ip;
            delete offerHashToIPOffer[offerHash].remainingQuantity;
        } else {
            // Delete cancelled offer completely from mapping if the market's RewardStyle is Upfront
            delete offerHashToIPOffer[offerHash];
        }

        emit IPOfferCancelled(offerHash);
    }

    /// @notice For wallets of Forfeitable markets, an AP can call this function to forgo their rewards and unlock their wallet
    function forfeit(address weirollWallet, bool executeWithdrawal) external payable isWeirollOwner(weirollWallet) nonReentrant {
        // Instantiate a weiroll wallet for the specified address
        WeirollWallet wallet = WeirollWallet(payable(weirollWallet));

        // Check that the wallet is forfeitable
        if (!wallet.isForfeitable()) {
            revert WalletNotForfeitable();
        }

        // Get locked reward params
        LockedRewardParams storage params = weirollWalletToLockedIncentivesParams[weirollWallet];

        // Forfeit wallet
        wallet.forfeit();

        // Setting this option to false allows the AP to be able to forfeit even when the withdrawal script is reverting
        if (executeWithdrawal) {
            // Execute the withdrawal script if flag set to true
            _executeWithdrawalScript(weirollWallet);
        }

        // Check if IP offer
        // If not, the forfeited amount won't be replenished to the offer
        if (params.wasIPOffer) {
            // Retrieve IP offer if it was one
            IPOffer storage offer = offerHashToIPOffer[params.offerHash];

            // Get amount filled by AP
            uint256 filledAmount = wallet.amount();

            // If IP address is 0, offer has been cancelled
            if (offer.ip == address(0) || (offer.expiry != 0 && offer.expiry < block.timestamp)) {
                // Cancelled or expired offer - return incentives that were originally held for the AP to the IP and take the fees
                uint256 fillPercentage = filledAmount.divWadDown(offer.quantity);

                // Get the ip from locked reward params
                address ip = params.ip;

                for (uint256 i = 0; i < params.incentives.length; ++i) {
                    address incentive = params.incentives[i];

                    // Calculate protocol fee to take based on percentage of fill
                    uint256 protocolFeeAmount = offer.incentiveToProtocolFeeAmount[incentive].mulWadDown(fillPercentage);
                    // Take protocol fee
                    _accountFee(protocolFeeClaimant, incentive, protocolFeeAmount, ip);

                    if (!PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
                        // Calculate frontend fee to refund to the IP on forfeit
                        uint256 frontendFeeAmount = offer.incentiveToFrontendFeeAmount[incentive].mulWadDown(fillPercentage);
                        // Refund incentive tokens and frontend fee to IP. Points don't need to be refunded.
                        ERC20(incentive).safeTransfer(ip, params.amounts[i] + frontendFeeAmount);
                    }

                    // Delete forfeited incentives and corresponding amounts from locked reward params
                    delete params.incentives[i];
                    delete params.amounts[i];

                    // Can't delete since there might be more forfeitable wallets still locked and we need to take fees on claim
                    // delete offer.incentiveToProtocolFeeAmount[incentive];
                    // delete offer.incentiveToFrontendFeeAmount[incentive];
                }
                // Can't delete since there might be more forfeitable wallets still locked
                // delete offerHashToIPOffer[params.offerHash];
            } else {
                // If not cancelled, add the filledAmount back to remaining quantity
                // Correct incentive amounts are still in this contract
                offer.remainingQuantity += filledAmount;

                // Delete forfeited incentives and corresponding amounts from locked reward params
                for (uint256 i = 0; i < params.incentives.length; ++i) {
                    delete params.incentives[i];
                    delete params.amounts[i];
                }
            }
        } else {
            // Get the protocol fee at fill and market frontend fee
            uint256 protocolFeeAtFill = params.protocolFeeAtFill;
            uint256 marketFrontendFee = marketHashToWeirollMarket[wallet.marketHash()].frontendFee;
            // Get the ip from locked reward params
            address ip = params.ip;

            // If offer was an AP offer, return the incentives to the IP and take the fee
            for (uint256 i = 0; i < params.incentives.length; ++i) {
                address incentive = params.incentives[i];
                uint256 amount = params.amounts[i];

                // Calculate fees to take based on percentage of fill
                uint256 protocolFeeAmount = amount.mulWadDown(protocolFeeAtFill);
                // Take fees
                _accountFee(protocolFeeClaimant, incentive, protocolFeeAmount, ip);

                if (!PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
                    // Calculate frontend fee to refund to the IP on forfeit
                    uint256 frontendFeeAmount = amount.mulWadDown(marketFrontendFee);
                    // Refund incentive tokens and frontend fee to IP. Points don't need to be refunded.
                    ERC20(incentive).safeTransfer(ip, amount + frontendFeeAmount);
                }

                // Delete forfeited incentives and corresponding amounts from locked reward params
                delete params.incentives[i];
                delete params.amounts[i];
            }
        }

        // Zero out the mapping
        delete weirollWalletToLockedIncentivesParams[weirollWallet];

        emit WeirollWalletForfeited(weirollWallet);
    }

    /// @notice Execute the withdrawal script in the weiroll wallet
    function executeWithdrawalScript(address weirollWallet) external payable isWeirollOwner(weirollWallet) weirollIsUnlocked(weirollWallet) nonReentrant {
        _executeWithdrawalScript(weirollWallet);
    }

    /// @param weirollWallet The wallet to claim for
    /// @param to The address to send the incentive to
    function claim(address weirollWallet, address to) external payable isWeirollOwner(weirollWallet) weirollIsUnlocked(weirollWallet) nonReentrant {
        // Get locked reward details to facilitate claim
        LockedRewardParams storage params = weirollWalletToLockedIncentivesParams[weirollWallet];

        // Instantiate a weiroll wallet for the specified address
        WeirollWallet wallet = WeirollWallet(payable(weirollWallet));

        // Get the frontend fee recipient and ip from locked reward params
        address frontendFeeRecipient = params.frontendFeeRecipient;
        address ip = params.ip;

        if (params.wasIPOffer) {
            // If it was an ipoffer, get the offer so we can retrieve the fee amounts and fill quantity
            IPOffer storage offer = offerHashToIPOffer[params.offerHash];

            uint256 fillAmount = wallet.amount();
            uint256 fillPercentage = fillAmount.divWadDown(offer.quantity);

            for (uint256 i = 0; i < params.incentives.length; ++i) {
                address incentive = params.incentives[i];

                // Calculate fees to take based on percentage of fill
                uint256 protocolFeeAmount = offer.incentiveToProtocolFeeAmount[incentive].mulWadDown(fillPercentage);
                uint256 frontendFeeAmount = offer.incentiveToFrontendFeeAmount[incentive].mulWadDown(fillPercentage);

                // Reward incentives to AP upon claim and account fees
                _pushIncentivesAndAccountFees(incentive, to, params.amounts[i], protocolFeeAmount, frontendFeeAmount, ip, frontendFeeRecipient);

                emit WeirollWalletClaimedIncentive(weirollWallet, to, incentive);

                /// Delete fields of dynamic arrays and mappings
                delete params.incentives[i];
                delete params.amounts[i];
            }
        } else {
            // Get the protocol fee at fill and market frontend fee
            uint256 protocolFeeAtFill = params.protocolFeeAtFill;
            uint256 marketFrontendFee = marketHashToWeirollMarket[wallet.marketHash()].frontendFee;

            for (uint256 i = 0; i < params.incentives.length; ++i) {
                address incentive = params.incentives[i];
                uint256 amount = params.amounts[i];

                // Calculate fees to take based on percentage of fill
                uint256 protocolFeeAmount = amount.mulWadDown(protocolFeeAtFill);
                uint256 frontendFeeAmount = amount.mulWadDown(marketFrontendFee);

                // Reward incentives to AP upon claim and account fees
                _pushIncentivesAndAccountFees(incentive, to, amount, protocolFeeAmount, frontendFeeAmount, ip, frontendFeeRecipient);

                emit WeirollWalletClaimedIncentive(weirollWallet, to, incentive);

                /// Delete fields of dynamic arrays and mappings
                delete params.incentives[i];
                delete params.amounts[i];
            }
        }

        // Zero out the mapping
        delete weirollWalletToLockedIncentivesParams[weirollWallet];
    }

    /// @param weirollWallet The wallet to claim for
    /// @param incentiveToken The incentiveToken to claim
    /// @param to The address to send the incentive to
    function claim(
        address weirollWallet,
        address incentiveToken,
        address to
    )
        external
        payable
        isWeirollOwner(weirollWallet)
        weirollIsUnlocked(weirollWallet)
        nonReentrant
    {
        // Get locked reward details to facilitate claim
        LockedRewardParams storage params = weirollWalletToLockedIncentivesParams[weirollWallet];

        // Instantiate a weiroll wallet for the specified address
        WeirollWallet wallet = WeirollWallet(payable(weirollWallet));

        // Get the frontend fee recipient and ip from locked reward params
        address frontendFeeRecipient = params.frontendFeeRecipient;
        address ip = params.ip;

        if (params.wasIPOffer) {
            // If it was an ipoffer, get the offer so we can retrieve the fee amounts and fill quantity
            IPOffer storage offer = offerHashToIPOffer[params.offerHash];

            // Calculate percentage of offer quantity this offer filled
            uint256 fillAmount = wallet.amount();
            uint256 fillPercentage = fillAmount.divWadDown(offer.quantity);

            for (uint256 i = 0; i < params.incentives.length; ++i) {
                address incentive = params.incentives[i];
                if (incentiveToken == incentive) {
                    // Calculate fees to take based on percentage of fill
                    uint256 protocolFeeAmount = offer.incentiveToProtocolFeeAmount[incentive].mulWadDown(fillPercentage);
                    uint256 frontendFeeAmount = offer.incentiveToFrontendFeeAmount[incentive].mulWadDown(fillPercentage);

                    // Reward incentives to AP upon claim and account fees
                    _pushIncentivesAndAccountFees(incentive, to, params.amounts[i], protocolFeeAmount, frontendFeeAmount, ip, frontendFeeRecipient);

                    emit WeirollWalletClaimedIncentive(weirollWallet, to, incentiveToken);

                    /// Delete fields of dynamic arrays and mappings once claimed
                    delete params.incentives[i];
                    delete params.amounts[i];

                    // Return upon claiming the incentive
                    return;
                }
            }
        } else {
            // Get the market frontend fee
            uint256 marketFrontendFee = marketHashToWeirollMarket[wallet.marketHash()].frontendFee;

            for (uint256 i = 0; i < params.incentives.length; ++i) {
                address incentive = params.incentives[i];
                if (incentiveToken == incentive) {
                    uint256 amount = params.amounts[i];

                    // Calculate fees to take based on percentage of fill
                    uint256 protocolFeeAmount = amount.mulWadDown(params.protocolFeeAtFill);
                    uint256 frontendFeeAmount = amount.mulWadDown(marketFrontendFee);

                    // Reward incentives to AP upon wallet unlock and account fees
                    _pushIncentivesAndAccountFees(incentive, to, amount, protocolFeeAmount, frontendFeeAmount, ip, frontendFeeRecipient);

                    emit WeirollWalletClaimedIncentive(weirollWallet, to, incentiveToken);

                    /// Delete fields of dynamic arrays and mappings
                    delete params.incentives[i];
                    delete params.amounts[i];

                    // Return upon claiming the incentive
                    return;
                }
            }
        }

        // This block will never get hit since array size doesn't get updated on delete
        // if (params.incentives.length == 0) {
        //     // Zero out the mapping if no more locked incentives to claim
        //     delete weirollWalletToLockedIncentivesParams[weirollWallet];
        // }
    }

    /// @param recipient The address to send fees to
    /// @param incentive The incentive address where fees are accrued in
    /// @param amount The amount of fees to award
    /// @param ip The incentive provider if awarding points
    function _accountFee(address recipient, address incentive, uint256 amount, address ip) internal {
        //check to see the incentive is actually a points campaign
        if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
            // Points cannot be claimed and are rather directly awarded
            Points(incentive).award(recipient, amount, ip);
        } else {
            feeClaimantToTokenToAmount[recipient][incentive] += amount;
        }
    }

    /// @param fundingVault The ERC4626 vault to fund the weiroll wallet with - if address(0) fund directly via AP
    /// @param ap The address of the AP to fund the weiroll wallet if no funding vault specified
    /// @param token The market input token to fund the weiroll wallet with
    /// @param amount The amount of market input token to fund the weiroll wallet with
    /// @param weirollWallet The weiroll wallet to fund with the specified amount of the market input token
    function _fundWeirollWallet(address fundingVault, address ap, ERC20 token, uint256 amount, address weirollWallet) internal {
        if (fundingVault == address(0)) {
            // If no fundingVault specified, fund the wallet directly from AP
            token.safeTransferFrom(ap, weirollWallet, amount);
        } else {
            // Withdraw the tokens from the funding vault into the wallet
            ERC4626(fundingVault).withdraw(amount, weirollWallet, ap);
            // Ensure that the Weiroll wallet received at least fillAmount of the inputToken from the AP provided vault
            if (token.balanceOf(weirollWallet) < amount) {
                revert WeirollWalletFundingFailed();
            }
        }
    }

    /**
     * @notice Handles the transfer and accounting of fees and incentives.
     * @dev This function is called internally to account fees and push incentives.
     * @param incentive The address of the incentive.
     * @param to The address of incentive recipient.
     * @param incentiveAmount The amount of the incentive token to be transferred.
     * @param protocolFeeAmount The protocol fee amount taken at fill.
     * @param frontendFeeAmount The frontend fee amount taken for this market.
     * @param ip The address of the action provider.
     * @param frontendFeeRecipient The address that will receive the frontend fee.
     */
    function _pushIncentivesAndAccountFees(
        address incentive,
        address to,
        uint256 incentiveAmount,
        uint256 protocolFeeAmount,
        uint256 frontendFeeAmount,
        address ip,
        address frontendFeeRecipient
    )
        internal
    {
        // Take fees
        _accountFee(protocolFeeClaimant, incentive, protocolFeeAmount, ip);
        _accountFee(frontendFeeRecipient, incentive, frontendFeeAmount, ip);

        // Push incentives to AP
        if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
            Points(incentive).award(to, incentiveAmount, ip);
        } else {
            ERC20(incentive).safeTransfer(to, incentiveAmount);
        }
    }

    /**
     * @notice Handles the transfer and accounting of fees and incentives for an AP offer fill.
     * @dev This function is called internally by `fillAPOffer` to manage the incentives.
     * @param incentive The address of the incentive.
     * @param incentiveAmount The amount of the incentive to be transferred.
     * @param protocolFeeAmount The protocol fee amount taken at fill.
     * @param frontendFeeAmount The frontend fee amount taken for this market.
     * @param ap The address of the action provider.
     * @param frontendFeeRecipient The address that will receive the frontend fee.
     * @param rewardStyle The style of reward distribution (Upfront, Arrear, Forfeitable).
     */
    function _pullIncentivesOnAPFill(
        address incentive,
        uint256 incentiveAmount,
        uint256 protocolFeeAmount,
        uint256 frontendFeeAmount,
        address ap,
        address frontendFeeRecipient,
        RewardStyle rewardStyle
    )
        internal
    {
        // msg.sender will always be IP
        if (rewardStyle == RewardStyle.Upfront) {
            // Take fees immediately from IP upon filling AP offers
            _accountFee(protocolFeeClaimant, incentive, protocolFeeAmount, msg.sender);
            _accountFee(frontendFeeRecipient, incentive, frontendFeeAmount, msg.sender);

            // Give incentives to AP immediately in an Upfront market
            if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
                // Award points on fill
                Points(incentive).award(ap, incentiveAmount, msg.sender);
            } else {
                // SafeTransferFrom does not check if a incentive address has any code, so we need to check it manually to prevent incentive deployment
                // frontrunning
                if (incentive.code.length == 0) {
                    revert TokenDoesNotExist();
                }
                // Transfer protcol and frontend fees to RecipeMarketHub for the claimants to withdraw them on-demand
                ERC20(incentive).safeTransferFrom(msg.sender, address(this), protocolFeeAmount + frontendFeeAmount);
                // Transfer AP's incentives to them on fill if token
                ERC20(incentive).safeTransferFrom(msg.sender, ap, incentiveAmount);
            }
        } else {
            // RewardStyle is Forfeitable or Arrear
            // If incentives will be paid out later, only handle the incentive case. Points will be awarded on claim.
            if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
                // If points incentive, make sure:
                // 1. The points factory used to create the program is the same as this RecipeMarketHubs PF
                // 2. IP placing the offer can award points
                // 3. Points factory has this RecipeMarketHub marked as a valid RO - can be assumed true
                if (POINTS_FACTORY != address(Points(incentive).pointsFactory()) || !Points(incentive).allowedIPs(msg.sender)) {
                    revert InvalidPointsProgram();
                }
            } else {
                // SafeTransferFrom does not check if a incentive address has any code, so we need to check it manually to prevent incentive deployment
                // frontrunning
                if (incentive.code.length == 0) {
                    revert TokenDoesNotExist();
                }
                // If not a points program, transfer amount requested (based on fill percentage) to the RecipeMarketHub in addition to protocol and frontend
                // fees.
                ERC20(incentive).safeTransferFrom(msg.sender, address(this), incentiveAmount + protocolFeeAmount + frontendFeeAmount);
            }
        }
    }

    /// @notice executes the withdrawal script for the provided weiroll wallet
    function _executeWithdrawalScript(address weirollWallet) internal {
        // Instantiate the WeirollWallet from the wallet address
        WeirollWallet wallet = WeirollWallet(payable(weirollWallet));

        // Get the market in offer to get the withdrawal recipe
        WeirollMarket storage market = marketHashToWeirollMarket[wallet.marketHash()];

        // Execute the withdrawal recipe
        wallet.executeWeiroll(market.withdrawRecipe.weirollCommands, market.withdrawRecipe.weirollState);

        emit WeirollWalletExecutedWithdrawal(weirollWallet);
    }
}
