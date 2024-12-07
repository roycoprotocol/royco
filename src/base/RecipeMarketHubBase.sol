// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { ERC20 } from "../../lib/solmate/src/tokens/ERC20.sol";
import { WeirollWallet } from "../WeirollWallet.sol";
import { ReentrancyGuardTransient } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import { Owned } from "../../lib/solmate/src/auth/Owned.sol";

enum RewardStyle {
    Upfront,
    Arrear,
    Forfeitable
}

/// @title RecipeMarketHubBase
/// @author Shivaansh Kapoor, Jack Corddry, CopyPaste
/// @notice Base contract for the RecipeMarketHub
abstract contract RecipeMarketHubBase is Owned, ReentrancyGuardTransient {
    /// @notice The address of the WeirollWallet implementation contract for use with ClonesWithImmutableArgs
    address public immutable WEIROLL_WALLET_IMPLEMENTATION;

    /// @notice The address of the PointsFactory contract
    address public immutable POINTS_FACTORY;

    /// @notice The minimum percent you can fill an AP offer with, to prevent griefing attacks
    uint256 public constant MIN_FILL_PERCENT = 0.1e18; // == 10%

    /// @dev The minimum quantity of tokens for an offer
    uint256 internal constant MINIMUM_QUANTITY = 1e6;

    /// @notice The number of AP offers that have been created
    uint256 public numAPOffers;
    /// @notice The number of IP offers that have been created
    uint256 public numIPOffers;
    /// @notice The number of unique weiroll markets added
    uint256 public numMarkets;

    /// @notice whether offer fills are paused
    bool offersPaused;

    /// @notice The percent deducted from the IP's incentive amount and claimable by protocolFeeClaimant
    uint256 public protocolFee; // 1e18 == 100% fee
    address public protocolFeeClaimant;

    /// @notice Markets can opt into a higher frontend fee to incentivize quick discovery but cannot go below this minimum
    uint256 public minimumFrontendFee; // 1e18 == 100% fee

    /// @notice Holds all WeirollMarket structs
    mapping(bytes32 => WeirollMarket) public marketHashToWeirollMarket;

    /// @notice Holds all IPOffer structs
    mapping(bytes32 => IPOffer) public offerHashToIPOffer;
    /// @notice Tracks the unfilled quantity of each AP offer
    mapping(bytes32 => uint256) public offerHashToRemainingQuantity;

    // Tracks the locked incentives associated with a weiroll wallet
    mapping(address => LockedRewardParams) public weirollWalletToLockedIncentivesParams;

    // Structure to store each fee claimant's accrued fees for a particular incentive token (claimant => incentive token => feesAccrued)
    mapping(address => mapping(address => uint256)) public feeClaimantToTokenToAmount;

    /// @custom:field weirollCommands The weiroll script that will be executed on an AP's weiroll wallet after receiving the inputToken
    /// @custom:field weirollState State of the weiroll VM, necessary for executing the weiroll script
    struct Recipe {
        bytes32[] weirollCommands;
        bytes[] weirollState;
    }

    /// @custom:field marketID The ID of the Weiroll Market
    /// @custom:field inputToken The token that will be deposited into the user's weiroll wallet for use in the recipe
    /// @custom:field lockupTime The time in seconds that the user's weiroll wallet will be locked up for after deposit
    /// @custom:field frontendFee The fee that the frontend will take from IP incentives, 1e18 == 100% fee
    /// @custom:field depositRecipe The weiroll recipe that will be executed after the inputToken is transferred to the wallet
    /// @custom:field withdrawRecipe The weiroll recipe that may be executed after lockupTime has passed to unwind a user's position
    struct WeirollMarket {
        uint256 marketID;
        ERC20 inputToken;
        uint256 lockupTime;
        uint256 frontendFee;
        Recipe depositRecipe;
        Recipe withdrawRecipe;
        RewardStyle rewardStyle;
    }

    /// @custom:field offerID Set to numAPOffers (zero-indexed) - ordered separately for AP and IP offers
    /// @custom:field targetMarketHash The hash of the weiroll market which the IP offer is for
    /// @custom:field ip The address of the incentive provider
    /// @custom:field expiry The timestamp after which the offer is considered expired
    /// @custom:field quantity The total quantity of the market's input token requested by the IP
    /// @custom:field incentivesOffered The incentives offered by the IP
    /// @custom:field incentiveAmountsOffered Mapping of incentive to the amount of the incentive allocated to APs
    /// @custom:field incentiveToProtocolFeeAmount Mapping of incentive to the amount of the incentive allocated to the protocol fee
    /// @custom:field incentiveToFrontendFeeAmount Mapping of incentive to the amount of the incentive allocated to frontend fee recipients
    struct IPOffer {
        uint256 offerID;
        bytes32 targetMarketHash;
        address ip;
        uint256 expiry;
        uint256 quantity;
        uint256 remainingQuantity;
        address[] incentivesOffered;
        mapping(address => uint256) incentiveAmountsOffered; // amounts to be allocated to APs (per incentive)
        mapping(address => uint256) incentiveToProtocolFeeAmount; // amounts to be allocated to protocolFeeClaimant (per incentive)
        mapping(address => uint256) incentiveToFrontendFeeAmount; // amounts to be allocated to frontend provider (per incentive)
    }

    /// @custom:field offerID Set to numAPOffers (zero-indexed) - ordered separately for AP and IP offers
    /// @custom:field targetMarketHash The hash of the weiroll market which the AP offer is for
    /// @custom:field ap The address of the action provider
    /// @custom:field fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @custom:field expiry The timestamp after which the offer is considered expired
    /// @custom:field quantity The total quantity of the market's input token offered by the AP
    /// @custom:field incentivesRequested The incentives requested by the AP
    /// @custom:field incentiveAmountsRequested The desired incentives per input token
    struct APOffer {
        uint256 offerID;
        bytes32 targetMarketHash;
        address ap;
        address fundingVault;
        uint256 quantity;
        uint256 expiry;
        address[] incentivesRequested;
        uint256[] incentiveAmountsRequested;
    }

    /// @custom:field incentives Tokens offered as incentives
    /// @custom:field amounts The amount of incentives offered for each incentive
    /// @custom:field ip The incentives provider
    struct LockedRewardParams {
        address[] incentives;
        uint256[] amounts;
        address ip;
        address frontendFeeRecipient;
        bool wasIPOffer;
        bytes32 offerHash; // For IP offer identification
        uint256 protocolFeeAtFill; // Used to keep track of protocol fee charged on fill for AP offers.
    }

    /// @custom:field marketID The ID of the newly created market
    /// @custom:field marketHash The hash of the newly created market
    /// @custom:field inputToken The token that will be deposited into the user's weiroll wallet for use in the recipe
    /// @custom:field lockupTime The time in seconds that the user's weiroll wallet will be locked up for after deposit
    /// @custom:field frontendFee The fee paid to the frontend out of IP incentives
    /// @custom:field rewardStyle Whether the rewards are paid at the beginning, locked until the end, or forfeitable until the end
    event MarketCreated(
        uint256 indexed marketID, bytes32 indexed marketHash, address indexed inputToken, uint256 lockupTime, uint256 frontendFee, RewardStyle rewardStyle
    );

    /// @param offerID Set to numAPOffers (zero-indexed) - ordered separately for AP and IP offers
    /// @param marketHash The hash of the weiroll market which the AP offer is for
    /// @param ap The address of the AP that created this offer.
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @param quantity The total amount of input tokens to be deposited
    /// @param incentiveAddresses The requested rewards
    /// @param incentiveAmounts The requested rewards per input token
    /// @param expiry The timestamp after which the offer is considered expired
    event APOfferCreated(
        uint256 indexed offerID,
        bytes32 indexed marketHash,
        address indexed ap,
        address fundingVault,
        uint256 quantity,
        address[] incentiveAddresses,
        uint256[] incentiveAmounts,
        uint256 expiry
    );

    /// @param offerID Set to numIPOffers (zero-indexed) - ordered separately for AP and IP offers
    /// @param offerHash Set to the hash of the offer (used to identify IP offers)
    /// @param marketHash The hash of the weiroll market which the IP offer is for
    /// @param ip The address of the IP that created this offer.
    /// @param quantity The total amount of input tokens to be deposited
    /// @param incentivesOffered The offered rewards
    /// @param incentiveAmounts The offered rewards per input token
    /// @param protocolFeeAmounts The offered rewards protocol fee per input token
    /// @param frontendFeeAmounts The offered rewards frontend fee per input token
    /// @param expiry The timestamp after which the offer is considered expired
    event IPOfferCreated(
        uint256 offerID,
        bytes32 indexed offerHash,
        bytes32 indexed marketHash,
        address indexed ip,
        uint256 quantity,
        address[] incentivesOffered,
        uint256[] incentiveAmounts,
        uint256[] protocolFeeAmounts,
        uint256[] frontendFeeAmounts,
        uint256 expiry
    );

    /// @param offerHash Hash of the offer (used to identify IP offers)
    /// @param ap The address of the AP that filled this offer.
    /// @param fillAmount The amount of the offer that was filled in the market input token
    /// @param weirollWallet The address of the weiroll wallet containing the AP's funds, created on fill, used to execute the recipes
    /// @param incentiveAmounts The amount of incentives allocated to the AP on fill (claimable as per the market's reward type)
    /// @param protocolFeeAmounts The protocol fee per incentive on fill (claimable as per the market's reward type)
    /// @param frontendFeeAmounts The rewards frontend fee per incentive on fill (claimable as per the market's reward type)
    event IPOfferFilled(
        bytes32 indexed offerHash,
        address indexed ap,
        uint256 fillAmount,
        address weirollWallet,
        uint256[] incentiveAmounts,
        uint256[] protocolFeeAmounts,
        uint256[] frontendFeeAmounts
    );

    /// @param offerID The ID of the AP offer filled
    /// @param ip The address of the IP that filled this offer.
    /// @param fillAmount The amount of the offer that was filled in the market input token
    /// @param weirollWallet The address of the weiroll wallet containing the AP's funds, created on fill, used to execute the recipes
    /// @param incentiveAmounts The amount of incentives allocated to the AP on fill (claimable as per the market's reward type)
    /// @param protocolFeeAmounts The amount taken as the protocol fee per incentive on fill (claimable as per the market's reward type)
    /// @param frontendFeeAmounts The amount taken as the frontend fee per incentive on fill (claimable as per the market's reward type)
    event APOfferFilled(
        uint256 indexed offerID,
        address indexed ip,
        uint256 fillAmount,
        address weirollWallet,
        uint256[] incentiveAmounts,
        uint256[] protocolFeeAmounts,
        uint256[] frontendFeeAmounts
    );

    /// @param offerHash The hash of the IP offer that was cancelled
    event IPOfferCancelled(bytes32 indexed offerHash);

    /// @param offerID The ID of the AP offer that was cancelled
    event APOfferCancelled(uint256 indexed offerID);

    /// @param claimant The address that claimed the fees
    /// @param incentive The address of the incentive claimed as a fee
    /// @param amount The amount of fees claimed
    event FeesClaimed(address indexed claimant, address indexed incentive, uint256 amount);

    /// @param weirollWallet The address of the weiroll wallet that forfeited
    event WeirollWalletForfeited(address indexed weirollWallet);

    /// @param weirollWallet The address of the weiroll wallet that claimed incentives
    /// @param recipient The address of the incentive recipient
    /// @param incentive The incentive claimed by the AP
    event WeirollWalletClaimedIncentive(address indexed weirollWallet, address recipient, address incentive);

    /// @param weirollWallet The address of the weiroll wallet that executed the withdrawal recipe
    event WeirollWalletExecutedWithdrawal(address indexed weirollWallet);

    /// @notice emitted when trying to create a market with address(0) as the input token
    error InvalidMarketInputToken();
    /// @notice emitted when trying to fill an offer that has expired
    error OfferExpired();
    /// @notice emitted when creating an offer with duplicate incentives
    error OfferCannotContainDuplicates();
    /// @notice emitted when trying to fill an offer with more input tokens than the remaining offer quantity
    error NotEnoughRemainingQuantity();
    /// @notice emitted when the base asset of the target vault and the funding vault do not match
    error MismatchedBaseAsset();
    /// @notice emitted if a market with the given ID does not exist
    error MarketDoesNotExist();
    /// @notice emitted when trying to place an offer with an expiry in the past
    error CannotPlaceExpiredOffer();
    /// @notice emitted when trying to place an offer with a quantity of 0
    error CannotPlaceZeroQuantityOffer();
    /// @notice emitted when incentives and amounts offered/requested arrays are not the same length
    error ArrayLengthMismatch();
    /// @notice emitted when the frontend fee is below the minimum
    error FrontendFeeTooLow();
    /// @notice emitted when trying to forfeit a wallet that is not owned by the caller
    error NotOwner();
    /// @notice emitted when trying to claim rewards of a wallet that is locked
    error WalletLocked();
    /// @notice Emitted when trying to start a rewards campaign with a non-existent incentive
    error TokenDoesNotExist();
    /// @notice Emitted when sum of protocolFee and frontendFee is greater than 100% (1e18)
    error TotalFeeTooHigh();
    /// @notice emitted when trying to fill an offer that doesn't exist anymore/yet
    error CannotFillZeroQuantityOffer();
    /// @notice emitted when funding the weiroll wallet with the market's input token failed
    error WeirollWalletFundingFailed();
    /// @notice emitted when creating an offer with an invalid points program
    error InvalidPointsProgram();
    /// @notice emitted when APOfferFill charges a trivial incentive amount
    error NoIncentivesPaidOnFill();
    /// @notice emitted when trying to fill offers while offers are paused
    error OffersPaused();
    /// @notice emitted when trying to forfeit a wallet where rewards are not forfeitable
    error WalletNotForfeitable();
    /// @notice emitted when trying to fill an offer with a quantity below the minimum fill percent
    error InsufficientFillPercent();

    /// @notice Modifier to check if msg.sender is owner of a weirollWallet
    modifier isWeirollOwner(address weirollWallet) {
        if (WeirollWallet(payable(weirollWallet)).owner() != msg.sender) {
            revert NotOwner();
        }
        _;
    }

    /// @notice Modifier to check if the weiroll wallet is unlocked
    modifier weirollIsUnlocked(address weirollWallet) {
        if (WeirollWallet(payable(weirollWallet)).lockedUntil() > block.timestamp) {
            revert WalletLocked();
        }
        _;
    }

    /// @notice Check if offer fills have been paused
    modifier offersNotPaused() {
        if (offersPaused) {
            revert OffersPaused();
        }
        _;
    }

    /// @notice Setter to pause and unpause fills
    function setOffersPaused(bool _offersPaused) external onlyOwner {
        offersPaused = _offersPaused;
    }

    /// @notice sets the protocol fee recipient, taken on all fills
    /// @param _protocolFeeClaimant The address allowed to claim protocol fees
    function setProtocolFeeClaimant(address _protocolFeeClaimant) external payable onlyOwner {
        protocolFeeClaimant = _protocolFeeClaimant;
    }

    /// @notice sets the protocol fee rate, taken on all fills
    /// @param _protocolFee The percent deducted from the IP's incentive amount and claimable by protocolFeeClaimant, 1e18 == 100% fee
    function setProtocolFee(uint256 _protocolFee) external payable onlyOwner {
        protocolFee = _protocolFee;
    }

    /// @notice sets the minimum frontend fee that a market can set and is paid to whoever fills the offer
    /// @param _minimumFrontendFee The minimum frontend fee for a market, 1e18 == 100% fee
    function setMinimumFrontendFee(uint256 _minimumFrontendFee) external payable onlyOwner {
        minimumFrontendFee = _minimumFrontendFee;
    }

    /// @notice Calculates the hash of a Weiroll Market
    function getMarketHash(WeirollMarket memory market) public pure returns (bytes32) {
        return keccak256(abi.encode(market));
    }

    /// @notice Calculates the hash of an AP offer
    function getAPOfferHash(APOffer memory offer) public pure returns (bytes32) {
        return keccak256(abi.encode(offer));
    }

    /// @notice Calculates the hash of an IP offer
    function getIPOfferHash(
        uint256 offerID,
        bytes32 targetMarketHash,
        address ip,
        uint256 expiry,
        uint256 quantity,
        address[] calldata incentivesOffered,
        uint256[] memory incentiveAmountsOffered
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(offerID, targetMarketHash, ip, expiry, quantity, incentivesOffered, incentiveAmountsOffered));
    }
}
