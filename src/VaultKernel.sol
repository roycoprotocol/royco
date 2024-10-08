// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC20 } from "../lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "../lib/solmate/src/tokens/ERC4626.sol";
import { WrappedVault } from "src/WrappedVault.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { Ownable2Step, Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ReentrancyGuardTransient } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";

/// @title VaultKernel
/// @author CopyPaste, corddry, ShivaanshK
/// @notice VaultKernel contract for Incentivizing AP/IPs to participate incentivized ERC4626 markets
contract VaultKernel is Ownable2Step, ReentrancyGuardTransient {
    using SafeTransferLib for ERC20;

    /// @custom:field offerID Set to numOffers - 1 on offer creation (zero-indexed)
    /// @custom:field targetVault The address of the vault where the input tokens will be deposited
    /// @custom:field ap The address of the liquidity provider
    /// @custom:field fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @custom:field expiry The timestamp after which the offer is considered expired
    /// @custom:field incentivesRequested The incentives requested by the AP in offer to fill the offer
    /// @custom:field incentivesRatesRequested The desired incentives per input token per second to fill the offer, measured in
    /// wei of incentives per wei of deposited assets per second, scaled up by 1e18 to avoid precision loss
    struct APOffer {
        uint256 offerID;
        address targetVault;
        address ap;
        address fundingVault;
        uint256 expiry;
        address[] incentivesRequested;
        uint256[] incentivesRatesRequested;
    }

    /// @notice starts at 0 and increments by 1 for each offer created
    uint256 public numOffers;

    /// @notice The minimum time a campaign must run for before someone can be allocated into it
    uint256 public constant MIN_CAMPAIGN_DURATION = 1 weeks;
    
    /// @notice whether offer fills are paused
    bool offersPaused;

    /// @notice maps offer hashes to the remaining quantity of the offer
    mapping(bytes32 => uint256) public offerHashToRemainingQuantity;

    /// @param offerID Set to numOffers - 1 on offer creation (zero-indexed)
    /// @param marketID The ID of the market to place the offer in
    /// @param fundingVault The address of the vault where the input tokens will be withdrawn from
    /// @param quantity The total amount of the base asset to be withdrawn from the funding vault
    /// @param incentivesRequested The incentives requested by the AP in offer to fill the offer
    /// @param incentivesRates The desired incentives per input token per second to fill the offer
    /// @param expiry The timestamp after which the offer is considered expired
    event APOfferCreated(
        uint256 indexed offerID,
        address indexed marketID,
        address fundingVault,
        uint256 quantity,
        address[] incentivesRequested,
        uint256[] incentivesRates,
        uint256 expiry
    );

    /// @notice emitted when an offer is cancelled and the remaining quantity is set to 0
    event APOfferCancelled(uint256 indexed offerID);

    /// @notice emitted when an AP is allocated to a vault
    event APOfferFilled(uint256 indexed offerID, uint256 fillAmount);

    /// @notice emitted when trying to fill an offer that has expired
    error OfferExpired();
    /// @notice emitted when trying to fill an offer with more input tokens than the remaining offer quantity
    error NotEnoughRemainingQuantity();
    /// @notice emitted when the base asset of the target vault and the funding vault do not match
    error MismatchedBaseAsset();
    /// @notice emitted when trying to fill a non-existent offer (remaining quantity of 0)
    error OfferDoesNotExist();
    /// @notice emitted when trying to create an offer with an expiry in the past
    error CannotPlaceExpiredOffer();
    /// @notice emitted when trying to allocate an AP, but the AP's requested incentives are not met
    error OfferConditionsNotMet();
    /// @notice emitted when trying to create an offer with a quantity of 0
    error CannotPlaceZeroQuantityOffer();
    /// @notice emitted when the AP does not have sufficient assets in the funding vault, or in their wallet to place an AP offer
    error NotEnoughBaseAssetToOffer();
    /// @notice emitted when the AP does not have sufficient assets in the funding vault, or in their wallet to allocate an offer
    error NotEnoughBaseAssetToAllocate();
    /// @notice emitted when the length of the incentives and prices arrays do not match
    error ArrayLengthMismatch();
    /// @notice emitted when the AP tries to cancel an offer that they did not create
    error NotOfferCreator();
    /// @notice emitted when the withdraw from funding vault fails on allocate
    error FundingVaultWithdrawFailed();
    /// @notice emitted when trying to fill offers while offers are paused
    error OffersPaused();

    modifier offersNotPaused() {
        if (offersPaused) {
            revert OffersPaused();
        }
        _;
    }

    function setOffersPaused(bool _offersPaused) external onlyOwner {
        offersPaused = _offersPaused;
    }

    constructor() Ownable(msg.sender) { }

    /// @dev Setting an expiry of 0 means the offer never expires
    /// @param targetVault The address of the vault where the liquidity will be deposited
    /// @param fundingVault The address of the vault where the liquidity will be withdrawn from, if set to 0, the AP will deposit the base asset directly
    /// @param quantity The total amount of the base asset to be withdrawn from the funding vault
    /// @param expiry The timestamp after which the offer is considered expired
    /// @param incentivesRequested The incentives requested by the AP in offer to fill the offer
    /// @param incentivesRatesRequested The desired incentives per input token per second to fill the offer
    function createAPOffer(
        address targetVault,
        address fundingVault,
        uint256 quantity,
        uint256 expiry,
        address[] calldata incentivesRequested,
        uint256[] calldata incentivesRatesRequested
    )
        public
        returns (uint256)
    {
        // Check offer isn't expired (expiries of 0 live forever)
        if (expiry != 0 && expiry < block.timestamp) {
            revert CannotPlaceExpiredOffer();
        }
        // Check offer isn't empty
        if (quantity == 0) {
            revert CannotPlaceZeroQuantityOffer();
        }
        // Check incentive and price arrays are the same length
        if (incentivesRequested.length != incentivesRatesRequested.length) {
            revert ArrayLengthMismatch();
        }
        // Check assets match in-kind
        // NOTE: The cool use of short-circuit means this call can't revert if fundingVault doesn't support asset()
        if (fundingVault != address(0) && ERC4626(targetVault).asset() != ERC4626(fundingVault).asset()) {
            revert MismatchedBaseAsset();
        }

        //Check that the AP has enough base asset in the funding vault for the offer
        if (fundingVault == address(0) && ERC20(ERC4626(targetVault).asset()).balanceOf(msg.sender) < quantity) {
            revert NotEnoughBaseAssetToOffer();
        } else if (fundingVault != address(0) && ERC4626(fundingVault).maxWithdraw(msg.sender) < quantity) {
            revert NotEnoughBaseAssetToOffer();
        }

        // Emit the offer creation event, used for matching offers
        emit APOfferCreated(numOffers, targetVault, fundingVault, quantity, incentivesRequested, incentivesRatesRequested, expiry);
        // Set the quantity of the offer
        APOffer memory offer = APOffer(numOffers, targetVault, msg.sender, fundingVault, expiry, incentivesRequested, incentivesRatesRequested);
        offerHashToRemainingQuantity[getOfferHash(offer)] = quantity;
        // Return the new offer's ID and increment the offer counter
        return (numOffers++);
    }

    /// @notice allocate the entirety of a given offer
    function allocateOffer(APOffer calldata offer) public offersNotPaused {
        allocateOffer(offer, offerHashToRemainingQuantity[getOfferHash(offer)]);
    }

    /// @notice allocate a specific quantity of a given offer
    function allocateOffer(APOffer calldata offer, uint256 fillAmount) public nonReentrant offersNotPaused {
        // Check for offer expiry, 0 expiries live forever
        if (offer.expiry != 0 && block.timestamp > offer.expiry) {
            revert OfferExpired();
        }

        bytes32 offerHash = getOfferHash(offer);

        {
            // Get remaining quantity
            uint256 remainingQuantity = offerHashToRemainingQuantity[offerHash];

            // Zero offers have been completely filled, cancelled, or never existed
            if (remainingQuantity == 0) {
                revert OfferDoesNotExist();
            }
            if (fillAmount > remainingQuantity) {
                // If fillAmount is max uint, fill the remaning, else revert
                if (fillAmount != type(uint256).max) {
                    revert NotEnoughRemainingQuantity();
                }
                fillAmount = remainingQuantity;
            }
        }

        //Check that the AP has enough base asset in the funding vault for the offer
        if (offer.fundingVault == address(0) && ERC20(ERC4626(offer.targetVault).asset()).balanceOf(offer.ap) < fillAmount) {
            revert NotEnoughBaseAssetToAllocate();
        } else if (offer.fundingVault != address(0) && ERC4626(offer.fundingVault).maxWithdraw(offer.ap) < fillAmount) {
            revert NotEnoughBaseAssetToAllocate();
        }

        // Reduce the remaining quantity of the offer
        offerHashToRemainingQuantity[offerHash] -= fillAmount;

        // if the fundingVault is set to 0, fund the fill directly via the base asset
        if (offer.fundingVault == address(0)) {
            // Transfer the base asset from the AP to the VaultKernel
            ERC4626(offer.targetVault).asset().safeTransferFrom(offer.ap, address(this), fillAmount);
        } else {
            // Get pre-withdraw token balance of VaultKernel
            uint256 preWithdrawTokenBalance = ERC4626(offer.targetVault).asset().balanceOf(address(this));

            // Withdraw from the funding vault to the VaultKernel
            ERC4626(offer.fundingVault).withdraw(fillAmount, address(this), offer.ap);

            // Get post-withdraw token balance of VaultKernel
            uint256 postWithdrawTokenBalance = ERC4626(offer.targetVault).asset().balanceOf(address(this));

            // Check that quantity withdrawn from the funding vault is at least the quantity to allocate
            if ((postWithdrawTokenBalance - preWithdrawTokenBalance) < fillAmount) {
                revert FundingVaultWithdrawFailed();
            }
        }

        for (uint256 i; i < offer.incentivesRatesRequested.length; ++i) {
            (uint32 start, uint32 end, ) = WrappedVault(offer.targetVault).rewardToInterval(offer.incentivesRequested[i]);
            if (end - start < MIN_CAMPAIGN_DURATION) {
                revert OfferConditionsNotMet();
            }
            if (offer.incentivesRatesRequested[i] > WrappedVault(offer.targetVault).previewRateAfterDeposit(offer.incentivesRequested[i], fillAmount)) {
                revert OfferConditionsNotMet();
            }
        }

        ERC4626(offer.targetVault).asset().safeApprove(offer.targetVault, 0);
        ERC4626(offer.targetVault).asset().safeApprove(offer.targetVault, fillAmount);

        // Deposit into the target vault
        ERC4626(offer.targetVault).deposit(fillAmount, offer.ap);

        emit APOfferFilled(offer.offerID, fillAmount);
    }

    /// @notice allocate a selection of offers
    function allocateOffers(APOffer[] calldata offers, uint256[] calldata fillAmounts) external {
        uint256 len = offers.length;
        for (uint256 i = 0; i < len; ++i) {
            allocateOffer(offers[i], fillAmounts[i]);
        }
    }

    /// @notice cancel an outstanding offer
    function cancelOffer(APOffer calldata offer) external {
        // Check if the AP is the creator of the offer
        if (offer.ap != msg.sender) {
            revert NotOfferCreator();
        }
        bytes32 offerHash = getOfferHash(offer);

        if (offerHashToRemainingQuantity[offerHash] == 0) {
            revert OfferDoesNotExist();
        }

        // Set the remaining quantity of the offer to 0, effectively cancelling it
        delete offerHashToRemainingQuantity[offerHash];

        emit APOfferCancelled(offer.offerID);
    }

    /// @notice calculate the hash of an offer
    function getOfferHash(APOffer memory offer) public pure returns (bytes32) {
        return keccak256(abi.encode(offer));
    }
}
