// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { RecipeMarketHubBase, RewardStyle, WeirollWallet } from "src/base/RecipeMarketHubBase.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "lib/solady/src/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "lib/solady/src/utils/SafeCastLib.sol";
import { Points } from "src/Points.sol";
import { PointsFactory } from "src/PointsFactory.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";

library GradualDutchAuction {
    error GDA__MulDivFailed();

    function _calculateIncentiveMultiplier(
        int256 decayRate,
        int256 emissionRate,
        int256 lastAuctionStartTime,
        uint256 numTokens
    )
        internal
        view
        returns (uint256)
    {
        int256 maxIntValue = type(int256).max; // 2**255 - 1
        int256 maxAllowed = 135e18;
        int256 quantity = SafeCastLib.toInt256(numTokens);
        int256 timeSinceLastAuctionStart = SafeCastLib.toInt256(block.timestamp) - lastAuctionStartTime;
        int256 num1 = FixedPointMathLib.rawSDivWad(1e18, decayRate);
        int256 exponent = FixedPointMathLib.expWad(_mulDiv(decayRate, quantity, emissionRate) * maxAllowed / maxIntValue) - 1;
        int256 den = FixedPointMathLib.expWad(decayRate * timeSinceLastAuctionStart / 1e18);

        int256 totalIncentiveMultiplier = (num1 * exponent) / den;
        return SafeCastLib.toUint256(totalIncentiveMultiplier);
    }

    /// @dev equivalent to `(x * y) / d` rounded down.
    function _mulDiv(int256 x, int256 y, int256 d) internal pure returns (int256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := mul(x, y)
            // equivalent to `require((x == 0 || z / x == y) && !(x == -1 && y == type(uint256).min))`
            if iszero(gt(or(iszero(x), eq(sdiv(z, x), y)), lt(not(x), eq(y, shl(255, 1))))) {
                mstore(0x00, 0xf96c5208) // `GDA__MulDivFailed()`
                revert(0x1c, 0x04)
            }
            z := sdiv(z, d)
        }
    }
}
