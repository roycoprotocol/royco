// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/WeirollWallet.sol";
import "../../../src/RecipeOrderbook.sol";
import "../../../src/PointsFactory.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { RoycoTestBase } from "../RoycoTestBase.sol";
import { RecipeUtils } from "./RecipeUtils.sol";

contract RecipeOrderbookTestBase is RoycoTestBase, RecipeUtils {
    // Contract deployments
    WeirollWallet public weirollImplementation;
    RecipeOrderbook public orderbook;
    MockERC20 public mockToken;
    MockERC4626 public mockVault;
    PointsFactory public pointsFactory;

    // Fees set in orderbook constructor
    uint256 initialProtocolFee;
    uint256 initialMinimumFrontendFee;

    function setUpRecipeOrderbookTests(uint256 _initialProtocolFee, uint256 _initialMinimumFrontendFee) public {
        setupBaseEnvironment();

        weirollImplementation = new WeirollWallet();
        mockToken = new MockERC20("Mock Token", "MT");
        mockVault = new MockERC4626(mockToken);
        pointsFactory = new PointsFactory();

        initialProtocolFee = _initialProtocolFee;
        initialMinimumFrontendFee = _initialMinimumFrontendFee;

        orderbook = new RecipeOrderbook(
            address(weirollImplementation),
            initialProtocolFee,
            initialMinimumFrontendFee,
            OWNER_ADDRESS, // fee claimant
            address(pointsFactory)
        );
    }
}
