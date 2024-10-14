// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";

import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";
import { AddressArrayUtils } from "../../utils/AddressArrayUtils.sol";
import { MockERC4626 } from "../../mocks/MockERC4626.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";

contract TestFuzz_APOfferCreation_RecipeKernel is RecipeKernelTestBase {
    using AddressArrayUtils for address[];
    
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);
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

        uint256 marketId = createMarket();
        address[] memory tokensRequested = new address[](_tokenCount);
        uint256[] memory tokenAmountsRequested = new uint256[](_tokenCount);

        uint256 expectedMarketId = recipeKernel.numAPOffers();

        // Generate random token addresses and counts
        for (uint256 i = 0; i < _tokenCount; i++) {
            tokensRequested[i] = address(uint160(uint256(keccak256(abi.encodePacked(expectedMarketId, i)))));
            tokenAmountsRequested[i] = (uint256(keccak256(abi.encodePacked(expectedMarketId, i)))) % 100_000e18 + 1e18;
        }

        tokensRequested.sort();

        // Generate a random quantity and valid expiry
        _quantity = _quantity % 100_000e18 + 1e6;
        _expiry = _expiry % 100_000 days + block.timestamp;

        address fundingVault = _fundingVaultSeed % 2 == 0 ? address(0) : address(mockVault);

        vm.expectEmit(true, true, true, true);
        emit RecipeKernelBase.APOfferCreated(0, marketId, fundingVault, _expiry, tokensRequested, tokenAmountsRequested, _quantity);

        bytes32 offerHash = recipeKernel.createAPOffer(marketId, fundingVault, _quantity, _expiry, tokensRequested, tokenAmountsRequested);

        assertEq(recipeKernel.numAPOffers(), expectedMarketId + 1);
        assertEq(recipeKernel.numIPOffers(), 0);
    }

    function TestFuzz_RevertIf_CreateAPOfferWithNonExistentMarket(uint256 _marketId) external {
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.MarketDoesNotExist.selector));
        recipeKernel.createAPOffer(
            _marketId, // Non-existent market ID
            address(0),
            100_000e18,
            block.timestamp + 1 days,
            new address[](1),
            new uint256[](1)
        );
    }

    function TestFuzz_RevertIf_CreateAPOfferWithZeroQuantity(uint256 _quantity) external {
        _quantity = _quantity % 1e6;

        uint256 marketId = createMarket();

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.CannotPlaceZeroQuantityOffer.selector));
        recipeKernel.createAPOffer(
            marketId,
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

        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.CannotPlaceExpiredOffer.selector));
        recipeKernel.createAPOffer(
            marketId,
            address(0),
            100_000e18,
            _expiry, // Expired timestamp
            new address[](1),
            new uint256[](1)
        );
    }

    function TestFuzz_RevertIf_CreateAPOfferWithMismatchedTokenArrays(uint8 _tokensRequestedLen, uint8 _tokenAmountsRequestedLen) external {
        vm.assume(_tokensRequestedLen != _tokenAmountsRequestedLen);

        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](_tokensRequestedLen);
        uint256[] memory tokenAmountsRequested = new uint256[](_tokenAmountsRequestedLen);

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.ArrayLengthMismatch.selector));
        recipeKernel.createAPOffer(marketId, address(0), 100_000e18, block.timestamp + 1 days, tokensRequested, tokenAmountsRequested);
    }

    function TestFuzz_RevertIf_CreateAPOfferWithMismatchedBaseAsset(string memory _tokenName, string memory _tokenSymbol) external {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        MockERC4626 mismatchedTokenVault = new MockERC4626(new MockERC20(_tokenName, _tokenSymbol));

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.MismatchedBaseAsset.selector));
        recipeKernel.createAPOffer(
            marketId,
            address(mismatchedTokenVault), // Funding vault with mismatched base asset
            100_000e18,
            block.timestamp + 1 days,
            tokensRequested,
            tokenAmountsRequested
        );
    }
}
