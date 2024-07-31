// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

contract TestOpportunity {
    ERC20 public token;

    constructor(ERC20 _token) {
        token = _token;
    }

    function withdraw(uint256 tokens) public {
        token.transfer(msg.sender, tokens);
    }
}
