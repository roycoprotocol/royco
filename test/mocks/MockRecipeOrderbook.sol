// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { RecipeOrderbook } from "src/RecipeOrderbook.sol";
import { RecipeOrderbookBase, RewardStyle, WeirollWallet } from "src/base/RecipeOrderbookBase.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { Points } from "src/Points.sol";
import { PointsFactory } from "src/PointsFactory.sol";

contract MockRecipeOrderbook is RecipeOrderbook {
    constructor(
        address _weirollWalletImplementation,
        uint256 _protocolFee,
        uint256 _minimumFrontendFee,
        address _owner,
        address _pointsFactory
    )
        RecipeOrderbook(_weirollWalletImplementation, _protocolFee, _minimumFrontendFee, _owner, _pointsFactory)
    { }

    function fillIPOrders(uint256 orderID, uint256 fillAmount, address fundingVault, address frontendFeeRecipient) external {
        _fillIPOrder(orderID, fillAmount, fundingVault, frontendFeeRecipient);
    }

    function fillAPOrders(APOrder calldata order, uint256 fillAmount, address frontendFeeRecipient) external {
        _fillAPOrder(order, fillAmount, frontendFeeRecipient);
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
}
