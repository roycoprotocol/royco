// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";

import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { AddressArrayUtils } from "../../utils/AddressArrayUtils.sol";
import { MockERC4626 } from "../../mocks/MockERC4626.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";

contract TestFuzz_APOfferCreation_RecipeMarketHub is RecipeMarketHubTestBase {
    using AddressArrayUtils for address[];

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function TestFuzz_CreateAPOffer(
        address _creator,
        uint256 _quantity,
        uint256 _expiry,
        uint256 _tokenCount,
        uint256 _fundingVaultSeed
    )
        external
        prankModifier(_creator)
    {
        _tokenCount = _tokenCount % 5 + 1; // bound token count between 1 and 5

        bytes32 marketHash = createMarket();
        address[] memory tokensRequested = new address[](_tokenCount);
        uint256[] memory tokenAmountsRequested = new uint256[](_tokenCount);

        uint256 expectedmarketHash = recipeMarketHub.numAPOffers();

        // Generate random token addresses and counts
        for (uint256 i = 0; i < _tokenCount; i++) {
            tokensRequested[i] = address(uint160(uint256(keccak256(abi.encodePacked(expectedmarketHash, i)))));
            tokenAmountsRequested[i] = (uint256(keccak256(abi.encodePacked(expectedmarketHash, i)))) % 100_000e18 + 1e18;
        }

        tokensRequested.sort();

        // Generate a random quantity and valid expiry
        _quantity = _quantity % 100_000e18 + 1e6;
        _expiry = _expiry % 100_000 days + block.timestamp;

        address fundingVault = _fundingVaultSeed % 2 == 0 ? address(0) : address(mockVault);

        vm.expectEmit(true, true, true, true);
        emit RecipeMarketHubBase.APOfferCreated(0, marketHash, address(0), fundingVault, _expiry, tokensRequested, tokenAmountsRequested, _quantity);

        bytes32 offerHash = recipeMarketHub.createAPOffer(marketHash, fundingVault, _quantity, _expiry, tokensRequested, tokenAmountsRequested);

        assertEq(recipeMarketHub.numAPOffers(), expectedmarketHash + 1);
        assertEq(recipeMarketHub.numIPOffers(), 0);
    }

    function TestFuzz_RevertIf_CreateAPOfferWithNonExistentMarket(bytes32 _marketHash) external {
        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.MarketDoesNotExist.selector));
        recipeMarketHub.createAPOffer(
            _marketHash, // Non-existent market ID
            address(0),
            100_000e18,
            block.timestamp + 1 days,
            new address[](1),
            new uint256[](1)
        );
    }

    function TestFuzz_RevertIf_CreateAPOfferWithZeroQuantity(uint256 _quantity) external {
        _quantity = _quantity % 1e6;

        bytes32 marketHash = createMarket();

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.CannotPlaceZeroQuantityOffer.selector));
        recipeMarketHub.createAPOffer(
            marketHash,
            address(0),
            _quantity, // Zero quantity
            block.timestamp + 1 days,
            new address[](1),
            new uint256[](1)
        );
    }

    function TestFuzz_RevertIf_CreateAPOfferWithExpiredOffer(uint256 _expiry, uint256 _blockTimestamp) external {
        vm.assume(_expiry > 0);
        vm.assume(_expiry < _blockTimestamp);
        vm.warp(_blockTimestamp); // set block timestamp

        bytes32 marketHash = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.CannotPlaceExpiredOffer.selector));
        recipeMarketHub.createAPOffer(
            marketHash,
            address(0),
            100_000e18,
            _expiry, // Expired timestamp
            new address[](1),
            new uint256[](1)
        );
    }

    function TestFuzz_RevertIf_CreateAPOfferWithMismatchedTokenArrays(uint8 _tokensRequestedLen, uint8 _tokenAmountsRequestedLen) external {
        vm.assume(_tokensRequestedLen != _tokenAmountsRequestedLen);

        bytes32 marketHash = createMarket();

        address[] memory tokensRequested = new address[](_tokensRequestedLen);
        uint256[] memory tokenAmountsRequested = new uint256[](_tokenAmountsRequestedLen);

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.ArrayLengthMismatch.selector));
        recipeMarketHub.createAPOffer(marketHash, address(0), 100_000e18, block.timestamp + 1 days, tokensRequested, tokenAmountsRequested);
    }

    function TestFuzz_RevertIf_CreateAPOfferWithMismatchedBaseAsset(string memory _tokenName, string memory _tokenSymbol) external {
        bytes32 marketHash = createMarket();

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        MockERC4626 mismatchedTokenVault = new MockERC4626(new MockERC20(_tokenName, _tokenSymbol));

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.MismatchedBaseAsset.selector));
        recipeMarketHub.createAPOffer(
            marketHash,
            address(mismatchedTokenVault), // Funding vault with mismatched base asset
            100_000e18,
            block.timestamp + 1 days,
            tokensRequested,
            tokenAmountsRequested
        );
    }
}
