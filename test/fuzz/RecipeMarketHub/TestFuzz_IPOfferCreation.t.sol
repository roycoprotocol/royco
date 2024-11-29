// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";
import "src/WrappedVault.sol";

import { MockERC20 } from "../../mocks/MockERC20.sol";
import { AddressArrayUtils } from "../../utils/AddressArrayUtils.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_IPOfferCreation_RecipeMarketHub is RecipeMarketHubTestBase {
    using FixedPointMathLib for uint256;
    using AddressArrayUtils for address[];

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_CreateIPOffer_ForToken(address _creator, uint256 _quantity, uint256 _expiry, uint256 _tokenCount) external prankModifier(_creator) {
        vm.assume(_creator != address(recipeMarketHub));
        _tokenCount = _tokenCount % 5 + 1; // Limit token count between 1 and 5
        bytes32 marketHash = createMarket();
        address[] memory incentivesOffered = new address[](_tokenCount);
        uint256[] memory incentiveAmountsOffered = new uint256[](_tokenCount);

        // Generate random token addresses and amounts
        for (uint256 i = 0; i < _tokenCount; i++) {
            address tokenAddress = address(uint160(uint256(keccak256(abi.encodePacked(marketHash, i)))));

            // Inject mock ERC20 bytecode into the token addresses
            MockERC20 mockToken = new MockERC20("Mock Token", "MKT");
            vm.etch(tokenAddress, address(mockToken).code);

            incentivesOffered[i] = tokenAddress;
            incentiveAmountsOffered[i] = (uint256(keccak256(abi.encodePacked(marketHash, i)))) % 100_000e18 + 1e18;
        }

        incentivesOffered.sort();

        for (uint256 i = 0; i < _tokenCount; i++) {
            MockERC20(incentivesOffered[i]).mint(_creator, incentiveAmountsOffered[i]);
            MockERC20(incentivesOffered[i]).approve(address(recipeMarketHub), incentiveAmountsOffered[i]);
        }

        _quantity = _quantity % 100_000e18 + 1e6; // Bound quantity
        _expiry = _expiry % 100_000 days + block.timestamp; // Bound expiry time

        // Calculate expected fees
        uint256[] memory protocolFeeAmount = new uint256[](_tokenCount);
        uint256[] memory frontendFeeAmount = new uint256[](_tokenCount);
        uint256[] memory incentiveAmount = new uint256[](_tokenCount);
        for (uint256 i = 0; i < _tokenCount; i++) {
            // Calculate expected fees
            (,,, uint256 frontendFee,,,) = recipeMarketHub.marketHashToWeirollMarket(marketHash);
            incentiveAmount[i] = incentiveAmountsOffered[i].divWadDown(1e18 + recipeMarketHub.protocolFee() + frontendFee);
            protocolFeeAmount[i] = incentiveAmount[i].mulWadDown(recipeMarketHub.protocolFee());
            frontendFeeAmount[i] = incentiveAmount[i].mulWadDown(frontendFee);
        }

        vm.expectEmit(true, true, true, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            recipeMarketHub.getOfferHash(0, marketHash, _creator, _expiry, _quantity, incentivesOffered, incentiveAmount),
            marketHash, // Market ID
            _creator,
            _quantity, // Total quantity
            incentivesOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            _expiry // Expiry time
        );

        // MockERC20 should track calls to `transferFrom`
        for (uint256 i = 0; i < _tokenCount; i++) {
            vm.expectCall(
                incentivesOffered[i],
                abi.encodeWithSelector(
                    ERC20.transferFrom.selector, _creator, address(recipeMarketHub), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]
                )
            );
        }

        // Create the IP offer
        bytes32 offerHash = recipeMarketHub.createIPOffer(
            marketHash, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            incentivesOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );

        // Assertions on the offer

        assertEq(recipeMarketHub.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeMarketHub.numAPOffers(), 0); // AP offers should remain 0

        for (uint256 i = 0; i < _tokenCount; i++) {
            // Use the helper function to retrieve values from storage
            uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, incentivesOffered[i]);
            uint256 protocolFeeAmountStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, incentivesOffered[i]);
            uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, incentivesOffered[i]);

            // Assert that the values match expected values
            assertEq(frontendFeeStored, frontendFeeAmount[i]);
            assertEq(incentiveAmountStored, incentiveAmount[i]);
            assertEq(protocolFeeAmountStored, protocolFeeAmount[i]);

            // Ensure the transfer was successful
            assertEq(MockERC20(incentivesOffered[i]).balanceOf(address(recipeMarketHub)), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]);
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
        vm.assume(_creator != address(recipeMarketHub));
        vm.assume(_pointsOwner != address(0));
        _programCount = _programCount % 5 + 1; // Limit program count between 1 and 5
        bytes32 marketHash = createMarket();

        address[] memory incentivesOffered = new address[](_programCount);
        uint256[] memory incentiveAmountsOffered = new uint256[](_programCount);

        // Create random Points programs and populate incentivesOffered array
        for (uint256 i = 0; i < _programCount; i++) {
            string memory name = string(abi.encodePacked("POINTS_", i));
            string memory symbol = string(abi.encodePacked("PTS_", i));

            // Create a new Points program
            Points points = pointsFactory.createPointsProgram(name, symbol, 18, _pointsOwner);

            // Allow ALICE to mint points in the Points program
            vm.startPrank(_pointsOwner);
            points.addAllowedIP(_creator);
            vm.stopPrank();

            // Add the Points program to the incentivesOffered array
            incentivesOffered[i] = address(points);
            incentiveAmountsOffered[i] = _quantity % 1000e18 + 1e6;
        }

        incentivesOffered.sort();

        _quantity = _quantity % 100_000e18 + 1e6; // Bound quantity
        _expiry = _expiry % 100_000 days + block.timestamp; // Bound expiry time

        // Calculate expected fees for each points program
        uint256[] memory protocolFeeAmount = new uint256[](_programCount);
        uint256[] memory frontendFeeAmount = new uint256[](_programCount);
        uint256[] memory incentiveAmount = new uint256[](_programCount);

        for (uint256 i = 0; i < _programCount; i++) {
            (,,, uint256 frontendFee,,,) = recipeMarketHub.marketHashToWeirollMarket(marketHash);
            incentiveAmount[i] = incentiveAmountsOffered[i].divWadDown(1e18 + recipeMarketHub.protocolFee() + frontendFee);
            protocolFeeAmount[i] = incentiveAmount[i].mulWadDown(recipeMarketHub.protocolFee());
            frontendFeeAmount[i] = incentiveAmount[i].mulWadDown(frontendFee);
        }

        vm.expectEmit(true, true, true, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            recipeMarketHub.getOfferHash(0, marketHash, _creator, _expiry, _quantity, incentivesOffered, incentiveAmount),
            marketHash, // Market ID
            _creator,
            _quantity, // Total quantity
            incentivesOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            _expiry // Expiry time
        );

        vm.startPrank(_creator);
        // Create the IP offer
        bytes32 offerHash = recipeMarketHub.createIPOffer(
            marketHash, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            incentivesOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
        vm.stopPrank();

        // Assertions on the offer

        assertEq(recipeMarketHub.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeMarketHub.numAPOffers(), 0); // AP offers should remain 0

        // Use the helper function to retrieve values from storage and assert them
        for (uint256 i = 0; i < _programCount; i++) {
            // Use the helper function to retrieve values from storage
            uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, incentivesOffered[i]);
            uint256 protocolFeeAmountStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, incentivesOffered[i]);
            uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, incentivesOffered[i]);

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
        vm.assume(_creator != address(recipeMarketHub));
        _tokenCount = _tokenCount % 3 + 1; // Limit token count between 1 and 3
        _programCount = _programCount % 3 + 1; // Limit program count between 1 and 3
        uint256 totalCount = _tokenCount + _programCount; // Total offered assets
        bytes32 marketHash = createMarket();

        address[] memory incentivesOffered = new address[](totalCount);
        uint256[] memory incentiveAmountsOffered = new uint256[](totalCount);

        // Create random ERC20 tokens and populate incentivesOffered array
        for (uint256 i = 0; i < _tokenCount; i++) {
            address tokenAddress = address(uint160(uint256(keccak256(abi.encodePacked(marketHash, i)))));

            // Inject mock ERC20 bytecode into the token addresses
            string memory name = string(abi.encodePacked("Mock_", i));
            string memory symbol = string(abi.encodePacked("MCK_", i));
            MockERC20 mockToken = new MockERC20(name, symbol);
            vm.etch(tokenAddress, address(mockToken).code);

            incentivesOffered[i] = tokenAddress;
        }

        // Create random Points programs and populate incentivesOffered array
        for (uint256 i = 0; i < _programCount; i++) {
            string memory name = string(abi.encodePacked("POINTS_", i));
            string memory symbol = string(abi.encodePacked("PTS_", i));

            // Create a new Points program
            Points points = pointsFactory.createPointsProgram(name, symbol, 18, _pointsOwner);

            // Allow the creator to mint points in the Points program
            vm.startPrank(_pointsOwner);
            points.addAllowedIP(_creator);
            vm.stopPrank();

            // Add the Points program to the incentivesOffered array after ERC20 tokens
            incentivesOffered[_tokenCount + i] = address(points);
            incentiveAmountsOffered[_tokenCount + i] = _quantity % 1000e18 + 1e18;
        }

        incentivesOffered.sort();

        for (uint256 i = 0; i < incentivesOffered.length; i++) {
            if (pointsFactory.isPointsProgram(incentivesOffered[i])) {
                continue;
            }

            incentiveAmountsOffered[i] = (uint256(keccak256(abi.encodePacked(marketHash, i)))) % 100_000e18 + 1e18;

            // Mint and approve tokens for the creator
            MockERC20(incentivesOffered[i]).mint(_creator, incentiveAmountsOffered[i]);
            vm.startPrank(_creator);
            MockERC20(incentivesOffered[i]).approve(address(recipeMarketHub), incentiveAmountsOffered[i]);
            vm.stopPrank();
        }

        _quantity = _quantity % 100_000e18 + 1e6; // Bound quantity
        _expiry = _expiry % 100_000 days + block.timestamp; // Bound expiry time

        // Calculate expected fees for both ERC20 tokens and Points programs
        uint256[] memory protocolFeeAmount = new uint256[](totalCount);
        uint256[] memory frontendFeeAmount = new uint256[](totalCount);
        uint256[] memory incentiveAmount = new uint256[](totalCount);

        for (uint256 i = 0; i < totalCount; i++) {
            (,,, uint256 frontendFee,,,) = recipeMarketHub.marketHashToWeirollMarket(marketHash);
            incentiveAmount[i] = incentiveAmountsOffered[i].divWadDown(1e18 + recipeMarketHub.protocolFee() + frontendFee);
            protocolFeeAmount[i] = incentiveAmount[i].mulWadDown(recipeMarketHub.protocolFee());
            frontendFeeAmount[i] = incentiveAmount[i].mulWadDown(frontendFee);
        }

        vm.expectEmit(true, true, true, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            recipeMarketHub.getOfferHash(0, marketHash, _creator, _expiry, _quantity, incentivesOffered, incentiveAmount),
            marketHash, // Market ID
            _creator,
            _quantity, // Total quantity
            incentivesOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            _expiry // Expiry time
        );

        // MockERC20 should track calls to `transferFrom` for ERC20 tokens
        for (uint256 i = 0; i < incentivesOffered.length; i++) {
            if (pointsFactory.isPointsProgram(incentivesOffered[i])) {
                continue;
            }
            vm.expectCall(
                incentivesOffered[i],
                abi.encodeWithSelector(
                    ERC20.transferFrom.selector, _creator, address(recipeMarketHub), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]
                )
            );
        }

        vm.startPrank(_creator);
        // Create the IP offer
        bytes32 offerHash = recipeMarketHub.createIPOffer(
            marketHash, // Referencing the created market
            _quantity, // Total input token amount
            _expiry, // Expiry time
            incentivesOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
        vm.stopPrank();

        // Assertions on the offer

        assertEq(recipeMarketHub.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeMarketHub.numAPOffers(), 0); // AP offers should remain 0

        // Use the helper function to retrieve values from storage and assert them
        for (uint256 i = 0; i < incentivesOffered.length; i++) {
            if (pointsFactory.isPointsProgram(incentivesOffered[i])) {
                continue;
            }
            // Use the helper function to retrieve values from storage
            uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, incentivesOffered[i]);
            uint256 protocolFeeAmountStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, incentivesOffered[i]);
            uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, incentivesOffered[i]);

            // Assert that the values match expected values
            assertEq(frontendFeeStored, frontendFeeAmount[i]);
            assertEq(incentiveAmountStored, incentiveAmount[i]);
            assertEq(protocolFeeAmountStored, protocolFeeAmount[i]);

            // Ensure the ERC20 transfer was successful
            assertEq(MockERC20(incentivesOffered[i]).balanceOf(address(recipeMarketHub)), protocolFeeAmount[i] + frontendFeeAmount[i] + incentiveAmount[i]);
        }

        for (uint256 i = _tokenCount; i < incentivesOffered.length; i++) {
            if (pointsFactory.isPointsProgram(incentivesOffered[i])) {
                continue;
            }
            // Use the helper function to retrieve values from storage
            uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, incentivesOffered[i]);
            uint256 protocolFeeAmountStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, incentivesOffered[i]);
            uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, incentivesOffered[i]);

            // Assert that the values match expected values
            assertEq(frontendFeeStored, frontendFeeAmount[i]);
            assertEq(incentiveAmountStored, incentiveAmount[i]);
            assertEq(protocolFeeAmountStored, protocolFeeAmount[i]);
        }
    }

    function testFuzz_RevertIf_CreateIPOfferWithNonExistentMarket(bytes32 _marketHash) external {
        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.MarketDoesNotExist.selector));
        recipeMarketHub.createIPOffer(
            _marketHash, // Non-existent market ID
            100_000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOfferWithZeroQuantity(uint256 _quantity) external {
        _quantity = _quantity % 1e6;

        bytes32 marketHash = createMarket();

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.CannotPlaceZeroQuantityOffer.selector));
        recipeMarketHub.createIPOffer(
            marketHash,
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

        bytes32 marketHash = createMarket();

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.CannotPlaceExpiredOffer.selector));
        recipeMarketHub.createIPOffer(
            marketHash,
            100_000e18, // Quantity
            _expiry, // Expired timestamp
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOfferWithNonexistentToken(address _tokenAddress) external {
        vm.assume(_tokenAddress.code.length == 0);
        vm.assume(_tokenAddress != address(0));
        bytes32 marketHash = createMarket();

        address[] memory incentivesOffered = new address[](1);
        incentivesOffered[0] = _tokenAddress;
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.TokenDoesNotExist.selector));
        recipeMarketHub.createIPOffer(
            marketHash,
            100_000e18, // Quantity
            1 days, // Expired timestamp
            incentivesOffered, // Empty tokens offered array
            incentiveAmountsOffered // Empty token amounts array
        );
    }

    function testFuzz_RevertIf_CreateIPOfferWithMismatchedTokenArrays(uint8 _incentivesOfferedLen, uint8 _incentiveAmountsOfferedLen) external {
        vm.assume(_incentivesOfferedLen != _incentiveAmountsOfferedLen);

        bytes32 marketHash = createMarket();

        address[] memory incentivesOffered = new address[](_incentivesOfferedLen);
        uint256[] memory incentiveAmountsOffered = new uint256[](_incentiveAmountsOfferedLen);

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.ArrayLengthMismatch.selector));
        recipeMarketHub.createIPOffer(
            marketHash,
            100_000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            incentivesOffered, // Mismatched arrays
            incentiveAmountsOffered
        );
    }
}
