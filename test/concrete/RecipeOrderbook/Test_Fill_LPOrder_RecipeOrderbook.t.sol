// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_Fill_LPOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    address IP_ADDRESS = ALICE_ADDRESS;
    address FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    

}