// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";
import "src/VaultWrapper.sol";

import { MockERC20 } from "../../mocks/MockERC20.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_IPOfferCreation_RecipeKernel is RecipeKernelTestBase {
    using FixedPointMathLib for uint256;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_CreateIPOffer_ForToken(address _creator, uint256 _quantity, uint256 _expiry, uint256 _tokenCount) external prankModifier(_creator) {
        vm.assume(_creator != address(recipeKernel));
        _tokenCount = _tokenCount % 5 + 1; // Limit token count between 1 and 5
        uint256 marketId = createMarket();
        address[] memory tokensOffered = new address[](_tokenCount);
        uint256[] memory incentiveAmountsOffered = new uint256[](_tokenCount);

        // Generate random token addresses and amounts
        for (uint256 i = 0; i < _tokenCount; i++) {
            address tokenAddress = address(uint160(uint256(keccak256(abi.encodePacked(marketId, i)))));

            // Inject mock ERC20 bytecode into the token addresses
            MockERC20 mockToken = new MockERC20("Mock Token", "MKT");
            vm.etch(tokenAddress, address(mockToken).code);

            tokensOffered[i] = tokenAddress;
            incentiveAmountsOffered[i] = (uint256(keccak256(abi.encodePacked(marketId, i)))) % 100_000e18 + 1e18;

            MockERC20(tokensOffered[i]).mint(_creator, incentiveAmountsOffered[i]);
            MockERC20(tokensOffered[i]).approve(address(recipeKernel), incentiveAmountsOffered[i]);
        }

        _quantity = _quantity % 100_000e18 + 1e6; // Bound quantity
        _expiry = _expiry % 100_000 days + block.timestamp; // Bound expiry time

        // Calculate expected fees
        uint256[] memory protocolFeeAmount = new uint256[](_tokenCount);
        uint256[] memory frontendFeeAmount = new uint256[](_tokenCount);
        uint256[] memory incentiveAmount = new uint256[](_tokenCount);
        for (uint256 i = 0; i < _tokenCount; i++) {
            // Calculate expected fees
            (,, uint256 frontendFee,,,) = recipeKernel.marketIDToWeirollMarket(marketId);
            incentiveAmount[i] = incentiveAmountsOffered[i].divWadDown(1e18 + recipeKernel.protocolFee() + frontendFee);
            protocolFeeAmount[i] = incentiveAmount[i].mulWadDown(recipeKernel.protocolFee());
            frontendFeeAmount[i] = incentiveAmount[i].mulWadDown(frontendFee);
        }

        vm.expectEmit(true, true, true, false, address(recipeKernel));
        emit RecipeKernelBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            marketId, // Market ID
            _quantity, // Total quantity
            tokensOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            _expiry // Expiry time
        );

        // MockERC20 should track calls to `transferFrom`
        for (uint256 i = 0; i < _tokenCount; i++) {
            vm.expectCall(
                tokensOffered[i],
                abi.encodeWithSelector(
                    ERC20.transferFrom.selector, _creator, address(recipeKernel), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]
                )
            );
        }

        // Create the IP offer
        uint256 offerId = recipeKernel.createIPOffer(
            marketId, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );

        // Assertions on the offer
        assertEq(offerId, 0); // First IP offer should have ID 0
        assertEq(recipeKernel.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeKernel.numAPOffers(), 0); // AP offers should remain 0

        for (uint256 i = 0; i < _tokenCount; i++) {
            // Use the helper function to retrieve values from storage
            uint256 frontendFeeStored = recipeKernel.getIncentiveToFrontendFeeAmountForIPOffer(offerId, tokensOffered[i]);
            uint256 protocolFeeAmountStored = recipeKernel.getIncentiveToProtocolFeeAmountForIPOffer(offerId, tokensOffered[i]);
            uint256 incentiveAmountStored = recipeKernel.getIncentiveAmountsOfferedForIPOffer(offerId, tokensOffered[i]);

            // Assert that the values match expected values
            assertEq(frontendFeeStored, frontendFeeAmount[i]);
            assertEq(incentiveAmountStored, incentiveAmount[i]);
            assertEq(protocolFeeAmountStored, protocolFeeAmount[i]);

            // Ensure the transfer was successful
            assertEq(MockERC20(tokensOffered[i]).balanceOf(address(recipeKernel)), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]);
        }
    }

    function testFuzz_CreateIPOffer_ForPointsProgram(
        address _creator,
        address _pointsOwner,
        uint256 _quantity,
        uint256 _expiry,
        uint256 _programCount
    )
        external
    {
        vm.assume(_creator != address(recipeKernel));
        vm.assume(_pointsOwner != address(0));
        _programCount = _programCount % 5 + 1; // Limit program count between 1 and 5
        uint256 marketId = createMarket();

        address[] memory tokensOffered = new address[](_programCount);
        uint256[] memory incentiveAmountsOffered = new uint256[](_programCount);

        // Create random Points programs and populate tokensOffered array
        for (uint256 i = 0; i < _programCount; i++) {
            string memory name = string(abi.encodePacked("POINTS_", i));
            string memory symbol = string(abi.encodePacked("PTS_", i));

            // Create a new Points program
            Points points = pointsFactory.createPointsProgram(name, symbol, 18, _pointsOwner);

            // Allow ALICE to mint points in the Points program
            vm.startPrank(_pointsOwner);
            points.addAllowedIP(_creator);
            vm.stopPrank();

            // Add the Points program to the tokensOffered array
            tokensOffered[i] = address(points);
            incentiveAmountsOffered[i] = _quantity % 1000e18 + 1e6;
        }

        _quantity = _quantity % 100_000e18 + 1e6; // Bound quantity
        _expiry = _expiry % 100_000 days + block.timestamp; // Bound expiry time

        // Calculate expected fees for each points program
        uint256[] memory protocolFeeAmount = new uint256[](_programCount);
        uint256[] memory frontendFeeAmount = new uint256[](_programCount);
        uint256[] memory incentiveAmount = new uint256[](_programCount);

        for (uint256 i = 0; i < _programCount; i++) {
            (,, uint256 frontendFee,,,) = recipeKernel.marketIDToWeirollMarket(marketId);
            incentiveAmount[i] = incentiveAmountsOffered[i].divWadDown(1e18 + recipeKernel.protocolFee() + frontendFee);
            protocolFeeAmount[i] = incentiveAmount[i].mulWadDown(recipeKernel.protocolFee());
            frontendFeeAmount[i] = incentiveAmount[i].mulWadDown(frontendFee);
        }

        vm.expectEmit(true, true, true, false, address(recipeKernel));
        emit RecipeKernelBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            marketId, // Market ID
            _quantity, // Total quantity
            tokensOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            _expiry // Expiry time
        );

        vm.startPrank(_creator);
        // Create the IP offer
        uint256 offerId = recipeKernel.createIPOffer(
            marketId, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
        vm.stopPrank();

        // Assertions on the offer
        assertEq(offerId, 0); // First IP offer should have ID 0
        assertEq(recipeKernel.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeKernel.numAPOffers(), 0); // AP offers should remain 0

        // Use the helper function to retrieve values from storage and assert them
        for (uint256 i = 0; i < _programCount; i++) {
            // Use the helper function to retrieve values from storage
            uint256 frontendFeeStored = recipeKernel.getIncentiveToFrontendFeeAmountForIPOffer(offerId, tokensOffered[i]);
            uint256 protocolFeeAmountStored = recipeKernel.getIncentiveToProtocolFeeAmountForIPOffer(offerId, tokensOffered[i]);
            uint256 incentiveAmountStored = recipeKernel.getIncentiveAmountsOfferedForIPOffer(offerId, tokensOffered[i]);

            // Assert that the values match expected values
            assertEq(frontendFeeStored, frontendFeeAmount[i]);
            assertEq(incentiveAmountStored, incentiveAmount[i]);
            assertEq(protocolFeeAmountStored, protocolFeeAmount[i]);
        }
    }

    function testFuzz_CreateIPOffer_ForTokensAndPoints(
        address _creator,
        address _pointsOwner,
        uint256 _quantity,
        uint256 _expiry,
        uint256 _tokenCount,
        uint256 _programCount
    )
        external
    {
        vm.assume(_pointsOwner != address(0));
        vm.assume(_creator != address(recipeKernel));
        _tokenCount = _tokenCount % 3 + 1; // Limit token count between 1 and 3
        _programCount = _programCount % 3 + 1; // Limit program count between 1 and 3
        uint256 totalCount = _tokenCount + _programCount; // Total offered assets
        uint256 marketId = createMarket();

        address[] memory tokensOffered = new address[](totalCount);
        uint256[] memory incentiveAmountsOffered = new uint256[](totalCount);

        // Create random ERC20 tokens and populate tokensOffered array
        for (uint256 i = 0; i < _tokenCount; i++) {
            address tokenAddress = address(uint160(uint256(keccak256(abi.encodePacked(marketId, i)))));

            // Inject mock ERC20 bytecode into the token addresses
            string memory name = string(abi.encodePacked("Mock_", i));
            string memory symbol = string(abi.encodePacked("MCK_", i));
            MockERC20 mockToken = new MockERC20(name, symbol);
            vm.etch(tokenAddress, address(mockToken).code);

            tokensOffered[i] = tokenAddress;
            incentiveAmountsOffered[i] = (uint256(keccak256(abi.encodePacked(marketId, i)))) % 100_000e18 + 1e18;

            // Mint and approve tokens for the creator
            MockERC20(tokensOffered[i]).mint(_creator, incentiveAmountsOffered[i]);
            vm.startPrank(_creator);
            MockERC20(tokensOffered[i]).approve(address(recipeKernel), incentiveAmountsOffered[i]);
            vm.stopPrank();
        }

        // Create random Points programs and populate tokensOffered array
        for (uint256 i = 0; i < _programCount; i++) {
            string memory name = string(abi.encodePacked("POINTS_", i));
            string memory symbol = string(abi.encodePacked("PTS_", i));

            // Create a new Points program
            Points points = pointsFactory.createPointsProgram(name, symbol, 18, _pointsOwner);

            // Allow the creator to mint points in the Points program
            vm.startPrank(_pointsOwner);
            points.addAllowedIP(_creator);
            vm.stopPrank();

            // Add the Points program to the tokensOffered array after ERC20 tokens
            tokensOffered[_tokenCount + i] = address(points);
            incentiveAmountsOffered[_tokenCount + i] = _quantity % 1000e18 + 1e18;
        }

        _quantity = _quantity % 100_000e18 + 1e6; // Bound quantity
        _expiry = _expiry % 100_000 days + block.timestamp; // Bound expiry time

        // Calculate expected fees for both ERC20 tokens and Points programs
        uint256[] memory protocolFeeAmount = new uint256[](totalCount);
        uint256[] memory frontendFeeAmount = new uint256[](totalCount);
        uint256[] memory incentiveAmount = new uint256[](totalCount);

        for (uint256 i = 0; i < totalCount; i++) {
            (,, uint256 frontendFee,,,) = recipeKernel.marketIDToWeirollMarket(marketId);
            incentiveAmount[i] = incentiveAmountsOffered[i].divWadDown(1e18 + recipeKernel.protocolFee() + frontendFee);
            protocolFeeAmount[i] = incentiveAmount[i].mulWadDown(recipeKernel.protocolFee());
            frontendFeeAmount[i] = incentiveAmount[i].mulWadDown(frontendFee);
        }

        vm.expectEmit(true, true, true, false, address(recipeKernel));
        emit RecipeKernelBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            marketId, // Market ID
            _quantity, // Total quantity
            tokensOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            _expiry // Expiry time
        );

        // MockERC20 should track calls to `transferFrom` for ERC20 tokens
        for (uint256 i = 0; i < _tokenCount; i++) {
            vm.expectCall(
                tokensOffered[i],
                abi.encodeWithSelector(
                    ERC20.transferFrom.selector, _creator, address(recipeKernel), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]
                )
            );
        }

        vm.startPrank(_creator);
        // Create the IP offer
        uint256 offerId = recipeKernel.createIPOffer(
            marketId, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
        vm.stopPrank();

        // Assertions on the offer
        assertEq(offerId, 0); // First IP offer should have ID 0
        assertEq(recipeKernel.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeKernel.numAPOffers(), 0); // AP offers should remain 0

        // Use the helper function to retrieve values from storage and assert them
        for (uint256 i = 0; i < _tokenCount; i++) {
            // Use the helper function to retrieve values from storage
            uint256 frontendFeeStored = recipeKernel.getIncentiveToFrontendFeeAmountForIPOffer(offerId, tokensOffered[i]);
            uint256 protocolFeeAmountStored = recipeKernel.getIncentiveToProtocolFeeAmountForIPOffer(offerId, tokensOffered[i]);
            uint256 incentiveAmountStored = recipeKernel.getIncentiveAmountsOfferedForIPOffer(offerId, tokensOffered[i]);

            // Assert that the values match expected values
            assertEq(frontendFeeStored, frontendFeeAmount[i]);
            assertEq(incentiveAmountStored, incentiveAmount[i]);
            assertEq(protocolFeeAmountStored, protocolFeeAmount[i]);

            // Ensure the ERC20 transfer was successful
            assertEq(MockERC20(tokensOffered[i]).balanceOf(address(recipeKernel)), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]);
        }

        for (uint256 i = _tokenCount; i < totalCount; i++) {
            // Use the helper function to retrieve values from storage
            uint256 frontendFeeStored = recipeKernel.getIncentiveToFrontendFeeAmountForIPOffer(offerId, tokensOffered[i]);
            uint256 protocolFeeAmountStored = recipeKernel.getIncentiveToProtocolFeeAmountForIPOffer(offerId, tokensOffered[i]);
            uint256 incentiveAmountStored = recipeKernel.getIncentiveAmountsOfferedForIPOffer(offerId, tokensOffered[i]);

            // Assert that the values match expected values
            assertEq(frontendFeeStored, frontendFeeAmount[i]);
            assertEq(incentiveAmountStored, incentiveAmount[i]);
            assertEq(protocolFeeAmountStored, protocolFeeAmount[i]);
        }
    }

    function testFuzz_RevertIf_CreateIPOfferWithNonExistentMarket(uint256 _marketId) external {
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.MarketDoesNotExist.selector));
        recipeKernel.createIPOffer(
            _marketId, // Non-existent market ID
            100_000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOfferWithZeroQuantity(uint256 _quantity) external {
        _quantity = _quantity % 1e6;

        uint256 marketId = createMarket();

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.CannotPlaceZeroQuantityOffer.selector));
        recipeKernel.createIPOffer(
            marketId,
            _quantity, // Zero quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOfferWithExpiredOffer(uint256 _expiry, uint256 _blockTimestamp) external {
        vm.assume(_expiry > 0);
        vm.assume(_expiry < _blockTimestamp);
        vm.warp(_blockTimestamp); // set block timestamp

        uint256 marketId = createMarket();

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.CannotPlaceExpiredOffer.selector));
        recipeKernel.createIPOffer(
            marketId,
            100_000e18, // Quantity
            _expiry, // Expired timestamp
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOfferWithNonexistentToken(address _tokenAddress) external {
        vm.assume(_tokenAddress.code.length == 0);
        uint256 marketId = createMarket();

        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = _tokenAddress;
        uint256[] memory incentiveAmountsOffered = new uint256[](2);
        incentiveAmountsOffered[0] = 1000e18;

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.TokenDoesNotExist.selector));
        recipeKernel.createIPOffer(
            marketId,
            100_000e18, // Quantity
            1 days, // Expired timestamp
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOfferWithMismatchedTokenArrays(uint8 _tokensOfferedLen, uint8 _incentiveAmountsOfferedLen) external {
        vm.assume(_tokensOfferedLen != _incentiveAmountsOfferedLen);

        uint256 marketId = createMarket();

        address[] memory tokensOffered = new address[](_tokensOfferedLen);
        uint256[] memory incentiveAmountsOffered = new uint256[](_incentiveAmountsOfferedLen);

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.ArrayLengthMismatch.selector));
        recipeKernel.createIPOffer(
            marketId,
            100_000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            tokensOffered, // Mismatched arrays
            incentiveAmountsOffered
        );
    }
}
