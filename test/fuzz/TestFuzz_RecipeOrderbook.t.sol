// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../src/WeirollWallet.sol";
import "../../src/RecipeOrderbook.sol";
import "../../src/PointsFactory.sol";

import { RecipeOrderbookTestBase } from "../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract TestFuzz_RecipeOrderbook is RecipeOrderbookTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_CreateOrderbook(
        uint256 _protocolFee,
        uint256 _minimumFrontendFee,
        address _weirollImplementation,
        address _ownerAddress,
        address _pointsFactory
    )
        external
    {
        vm.assume(_ownerAddress != address(0));
        vm.assume(_protocolFee <= 1e18);
        vm.assume(_minimumFrontendFee <= 1e18);
        vm.assume((_protocolFee + _minimumFrontendFee) <= 1e18);

        // Deploy orderbook and check for ownership transfer
        vm.expectEmit(true, false, false, true);
        emit Ownable.OwnershipTransferred(address(0), _ownerAddress);
        RecipeOrderbook newOrderbook = new RecipeOrderbook(
            _weirollImplementation,
            _protocolFee,
            _minimumFrontendFee,
            _ownerAddress, // fee claimant
            _pointsFactory
        );
        // Check constructor args being set correctly
        assertEq(newOrderbook.WEIROLL_WALLET_IMPLEMENTATION(), _weirollImplementation);
        assertEq(newOrderbook.POINTS_FACTORY(), _pointsFactory);
        assertEq(newOrderbook.protocolFee(), _protocolFee);
        assertEq(newOrderbook.protocolFeeClaimant(), _ownerAddress);
        assertEq(newOrderbook.minimumFrontendFee(), _minimumFrontendFee);

        // Check initial orderbook state
        assertEq(newOrderbook.numLPOrders(), 0);
        assertEq(newOrderbook.numIPOrders(), 0);
        assertEq(newOrderbook.numMarkets(), 0);
    }

    function testFuzz_SetProtocolFeeClaimant(address _newClaimant) external prankModifier(OWNER_ADDRESS) {
        assertEq(orderbook.protocolFeeClaimant(), OWNER_ADDRESS);
        orderbook.setProtocolFeeClaimant(_newClaimant);
        assertEq(orderbook.protocolFeeClaimant(), _newClaimant);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFeeClaimant(address _nonOwner, address _newClaimant) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _nonOwner));
        orderbook.setProtocolFeeClaimant(_newClaimant);
    }

    function testFuzz_SetProtocolFee(uint256 _newProtocolFee) external prankModifier(OWNER_ADDRESS) {
        orderbook.setProtocolFee(_newProtocolFee);
        assertEq(orderbook.protocolFee(), _newProtocolFee);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFee(address _nonOwner, uint256 _newProtocolFee) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _nonOwner));
        orderbook.setProtocolFee(_newProtocolFee);
    }

    function testFuzz_SetMinimumFrontendFee(uint256 _newMinimumFrontendFee) external prankModifier(OWNER_ADDRESS) {
        orderbook.setMinimumFrontendFee(_newMinimumFrontendFee);
        assertEq(orderbook.minimumFrontendFee(), _newMinimumFrontendFee);
    }

    function testFuzz_RevertIf_NonOwnerSetMinimumFrontendFee(address _nonOwner, uint256 _newMinimumFrontendFee) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _nonOwner));
        orderbook.setMinimumFrontendFee(_newMinimumFrontendFee);
    }

    function testFuzz_CreateMarket(
        uint256 _lockupTime,
        uint256 _frontendFee,
        uint8 _depositRecipeCommandCount,
        uint8 _depositRecipeStateCount,
        uint8 _withdrawalRecipeCommandCount,
        uint8 _withdrawalRecipeStateCount,
        address _inputTokenAddress,
        uint8 _rewardStyle
    )
        external
    {
        // Manually bound the inputs using modulo to limit the ranges (was hitting fuzzing reject limit)
        _frontendFee = initialMinimumFrontendFee + (_frontendFee % (1e18 - initialMinimumFrontendFee)); // Frontend fee between min fee and 100%
        // Limit recipe counts to a maximum of 10 for commands and 5 for state entries
        _depositRecipeCommandCount = _depositRecipeCommandCount % 10;
        _depositRecipeStateCount = _depositRecipeStateCount % 5;
        _withdrawalRecipeCommandCount = _withdrawalRecipeCommandCount % 10;
        _withdrawalRecipeStateCount = _withdrawalRecipeStateCount % 5;
        // Bound reward style to valid enum values (0, 1, 2)
        _rewardStyle = _rewardStyle % 3;

        // Convert the fuzzed reward style index to the actual enum
        RewardStyle rewardStyle = RewardStyle(_rewardStyle);

        // Generate random recipes for deposit and withdrawal
        RecipeOrderbook.Recipe memory depositRecipe = generateRandomRecipe(_depositRecipeCommandCount, _depositRecipeStateCount);
        RecipeOrderbook.Recipe memory withdrawRecipe = generateRandomRecipe(_withdrawalRecipeCommandCount, _withdrawalRecipeStateCount);

        // Get the expected market ID
        uint256 expectedMarketId = orderbook.numMarkets();

        // Check for MarketCreated event
        vm.expectEmit(true, true, false, true, address(orderbook));
        emit RecipeOrderbook.MarketCreated(expectedMarketId, _inputTokenAddress, _lockupTime, _frontendFee, rewardStyle);

        // Call createMarket with the fuzzed inputs
        uint256 marketId = orderbook.createMarket(_inputTokenAddress, _lockupTime, _frontendFee, depositRecipe, withdrawRecipe, rewardStyle);

        // Assert basic orderbook market state
        assertEq(marketId, expectedMarketId);
        assertEq(orderbook.numMarkets(), expectedMarketId + 1);

        // Check that the market was added correctly
        (
            ERC20 resultingInputToken,
            uint256 resultingLockupTime,
            uint256 resultingFrontendFee,
            RecipeOrderbook.Recipe memory resultingDepositRecipe,
            RecipeOrderbook.Recipe memory resultingWithdrawRecipe,
            RewardStyle resultingRewardStyle
        ) = orderbook.marketIDToWeirollMarket(marketId);

        // Ensure the resulting market matches the inputs
        assertEq(address(resultingInputToken), _inputTokenAddress);
        assertEq(resultingLockupTime, _lockupTime);
        assertEq(resultingFrontendFee, _frontendFee);
        assertEq(resultingDepositRecipe.weirollCommands, depositRecipe.weirollCommands);
        assertEq(resultingDepositRecipe.weirollState, depositRecipe.weirollState);
        assertEq(resultingWithdrawRecipe.weirollCommands, withdrawRecipe.weirollCommands);
        assertEq(resultingWithdrawRecipe.weirollState, withdrawRecipe.weirollState);
        assertEq(uint8(resultingRewardStyle), uint8(rewardStyle));
    }

    function testFuzz_RevertIf_CreateMarketWithInvalidFrontendFee(uint256 _initialMinimumFrontendFee, uint256 _marketFrontendFee) external {
        // Make sure that the market fee is less than minimum fee so it reverts
        vm.assume(_marketFrontendFee < _initialMinimumFrontendFee);

        // Protocol fee doesn't matter for this test, so set to 1%
        setUpRecipeOrderbookTests(0.01e18, _initialMinimumFrontendFee);

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.FrontendFeeTooLow.selector));
        orderbook.createMarket(
            address(mockToken),
            1 days, // Weiroll wallet lockup time
            _marketFrontendFee, // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }
}
