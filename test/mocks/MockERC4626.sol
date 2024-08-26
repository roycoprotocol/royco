// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/solmate/src/tokens/ERC20.sol";
import "lib/solmate/src/tokens/ERC4626.sol";

contract MockERC4626 is ERC4626 {
    constructor(ERC20 _asset) ERC4626(_asset, "Base Vault", "bVault") {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
