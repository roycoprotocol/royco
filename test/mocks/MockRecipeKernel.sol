// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { RecipeKernel } from "src/RecipeKernel.sol";
import { RecipeKernelBase, RewardStyle, WeirollWallet } from "src/base/RecipeKernelBase.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { Points } from "src/Points.sol";
import { PointsFactory } from "src/PointsFactory.sol";

contract MockRecipeKernel is RecipeKernel {
    constructor(
        address _weirollWalletImplementation,
        uint256 _protocolFee,
        uint256 _minimumFrontendFee,
        address _owner,
        address _pointsFactory
    )
        RecipeKernel(_weirollWalletImplementation, _protocolFee, _minimumFrontendFee, _owner, _pointsFactory)
    { }

    function fillIPOffers(uint256 offerID, uint256 fillAmount, address fundingVault, address frontendFeeRecipient) external {
        _fillIPOffer(offerID, fillAmount, fundingVault, frontendFeeRecipient);
    }

    function fillAPOffers(APOffer calldata offer, uint256 fillAmount, address frontendFeeRecipient) external {
        _fillAPOffer(offer, fillAmount, frontendFeeRecipient);
    }

    // Getters to access nested mappings
    function getIncentiveAmountsOfferedForIPOffer(uint256 offerId, address tokenAddress) external view returns (uint256) {
        return offerIDToIPOffer[offerId].incentiveAmountsOffered[tokenAddress];
    }

    function getIncentiveToProtocolFeeAmountForIPOffer(uint256 offerId, address tokenAddress) external view returns (uint256) {
        return offerIDToIPOffer[offerId].incentiveToProtocolFeeAmount[tokenAddress];
    }

    function getIncentiveToFrontendFeeAmountForIPOffer(uint256 offerId, address tokenAddress) external view returns (uint256) {
        return offerIDToIPOffer[offerId].incentiveToFrontendFeeAmount[tokenAddress];
    }

    // Single getter function that returns the entire LockedRewardParams struct as a tuple
    function getLockedIncentiveParams(address weirollWallet) external view returns (address[] memory incentives, uint256[] memory amounts, address ip) {
        LockedRewardParams storage params = weirollWalletToLockedIncentivesParams[weirollWallet];
        return (params.incentives, params.amounts, params.ip);
    }
}
