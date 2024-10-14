// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";

import { WrappedVault } from "src/WrappedVault.sol";
import { WrappedVaultFactory } from "src/WrappedVaultFactory.sol";

import { WeirollWallet } from "src/WeirollWallet.sol";

import { PointsFactory } from "src/PointsFactory.sol";
import { Points } from "src/Points.sol";

import { VaultMarketHub } from "src/VaultMarketHub.sol";
import "test/mocks/MockRecipeMarketHub.sol";

import { Test, console } from "forge-std/Test.sol";

contract ScenarioTest is Test {
    VaultMarketHub public vaultMarketHub;
    MockRecipeMarketHub public recipeMarketHub;

    WeirollWallet public weirollImplementation = new WeirollWallet();
    PointsFactory public pointsFactory = new PointsFactory(POINTS_FACTORY_OWNER);

    address public constant POINTS_FACTORY_OWNER = address(0xbeef);
    address public USER01 = address(0x01);
    address public USER02 = address(0x02);

    address public OWNER_ADDRESS = address(0x05);
    address public FRONTEND_FEE_RECIPIENT = address(0x06);

    MockERC20 public baseToken;
    MockERC20 public baseToken2;
    MockERC4626 public targetVault;
    MockERC4626 public targetVault2;
    MockERC4626 public targetVault3;
    MockERC4626 public fundingVault;
    MockERC4626 public fundingVault2;

    uint256 initialProtocolFee = 0.05e18;
    uint256 initialMinimumFrontendFee = 0.025e18;

    RecipeMarketHub.Recipe NULL_RECIPE = RecipeMarketHubBase.Recipe(new bytes32[](0), new bytes[](0));

    function setUp() public {
        baseToken = new MockERC20("Base Token", "BT");
        baseToken2 = new MockERC20("Base Token2", "BT2");

        targetVault = new MockERC4626(baseToken);
        targetVault2 = new MockERC4626(baseToken);
        targetVault3 = new MockERC4626(baseToken);
        fundingVault = new MockERC4626(baseToken);
        fundingVault2 = new MockERC4626(baseToken2);

        recipeMarketHub = new MockRecipeMarketHub(
            address(weirollImplementation),
            initialProtocolFee,
            initialMinimumFrontendFee,
            OWNER_ADDRESS, // fee claimant
            address(pointsFactory)
        );

        vaultMarketHub = new VaultMarketHub(address(this));
    }

    function testBasicVaultMarketHubAllocate() public {
        vm.startPrank(USER01);
        baseToken.mint(USER01, 1000 * 1e18);
        baseToken.approve(address(vaultMarketHub), 300 * 1e18);
        baseToken.approve(address(fundingVault), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        uint256 offer1Id =
            vaultMarketHub.createAPOffer(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        uint256 offer2Id =
            vaultMarketHub.createAPOffer(address(targetVault2), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        uint256 offer3Id =
            vaultMarketHub.createAPOffer(address(targetVault3), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultMarketHub.APOffer memory offer1 =
            VaultMarketHub.APOffer(offer1Id, address(targetVault), USER01, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultMarketHub.APOffer memory offer2 =
            VaultMarketHub.APOffer(offer2Id, address(targetVault2), USER01, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultMarketHub.APOffer memory offer3 =
            VaultMarketHub.APOffer(offer3Id, address(targetVault3), USER01, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        uint256[][] memory moreCampaignIds = new uint256[][](3);
        moreCampaignIds[0] = new uint256[](1);
        moreCampaignIds[0][0] = 0;
        moreCampaignIds[1] = new uint256[](1);
        moreCampaignIds[1][0] = 1;
        moreCampaignIds[2] = new uint256[](1);
        moreCampaignIds[2][0] = 2;
        VaultMarketHub.APOffer[] memory offers = new VaultMarketHub.APOffer[](3);

        bytes32 offer1Hash = vaultMarketHub.getOfferHash(offer1);
        bytes32 offer2Hash = vaultMarketHub.getOfferHash(offer2);
        bytes32 offer3Hash = vaultMarketHub.getOfferHash(offer3);

        offers[0] = offer1;
        offers[1] = offer2;
        offers[2] = offer3;

        // Mock the previewRateAfterDeposit function
        vm.mockCall(
            address(targetVault), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
        vm.mockCall(
            address(targetVault), abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), uint256(100 * 1e18)), abi.encode(2e18)
        );
        vm.mockCall(
            address(targetVault2), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
        vm.mockCall(
            address(targetVault2), abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), uint256(100 * 1e18)), abi.encode(2e18)
        );
        vm.mockCall(
            address(targetVault3), abi.encodeWithSignature("rewardToInterval(address)", address(baseToken)), abi.encode(uint32(1 days), uint32(10 days), uint96(0))
        );
        vm.mockCall(
            address(targetVault3), abi.encodeWithSelector(WrappedVault.previewRateAfterDeposit.selector, address(baseToken), uint256(100 * 1e18)), abi.encode(2e18)
        );

        uint256[] memory fillAmounts = new uint256[](3);
        fillAmounts[0] = type(uint256).max;
        fillAmounts[1] = type(uint256).max;
        fillAmounts[2] = type(uint256).max;
        vaultMarketHub.allocateOffers(offers, fillAmounts);

        //Verify none of the offers allocated
        assertEq(targetVault.balanceOf(USER01), 100 * 1e18);
        assertEq(targetVault2.balanceOf(USER01), 100 * 1e18);
        assertEq(targetVault3.balanceOf(USER01), 100 * 1e18);

        assertEq(vaultMarketHub.offerHashToRemainingQuantity(offer1Hash), 0);
        assertEq(vaultMarketHub.offerHashToRemainingQuantity(offer2Hash), 0);
        assertEq(vaultMarketHub.offerHashToRemainingQuantity(offer3Hash), 0);

        assertEq(baseToken.balanceOf(address(USER01)), 1000 * 1e18 - 300 * 1e18);

        vm.stopPrank();
    }

    function testBasicRecipeMarketHubAllocate() public {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(baseToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        vm.startPrank(USER02);
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(baseToken2);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        baseToken2.mint(USER02, 1000e18);
        baseToken2.approve(address(recipeMarketHub), 1000e18);

        bytes32 offerHash = recipeMarketHub.createIPOffer(
            marketHash, // Referencing the created market
            offerAmount, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
        vm.stopPrank();

        // Mint liquidity tokens to the AP to fill the offer
        baseToken.mint(USER01, fillAmount);
        vm.startPrank(USER01);
        baseToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        // Fill the offer
        vm.startPrank(USER01);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);
    }
}
