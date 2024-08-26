// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

contract Lock {
    function depositTokens(address token, address sender, uint256 amount) public payable {
        ERC20 erc20 = ERC20(token);

        // Transfer the tokens from the sender to the contract
        // working
        // token.transfer(address(this), amount);

        erc20.transferFrom(sender, address(this), amount);
    }

    function withdrawTokens(address token, address recipient, uint256 amount) public payable {
        ERC20 erc20 = ERC20(token);

        erc20.transfer(recipient, amount);
    }
}
