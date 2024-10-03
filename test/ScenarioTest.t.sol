// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";

import { ERC4626i } from "src/ERC4626i.sol";
import { ERC4626iFactory } from "src/ERC4626iFactory.sol";

import { WeirollWallet } from "src/WeirollWallet.sol";

import { PointsFactory } from "src/PointsFactory.sol";
import { Points } from "src/Points.sol";

import { VaultOrderbook } from "src/VaultOrderbook.sol";
import "test/mocks/MockRecipeOrderbook.sol";

import { Test, console } from "forge-std/Test.sol";

contract ScenarioTest is Test {
    VaultOrderbook public vaultOrderbook;
    MockRecipeOrderbook public recipeOrderbook;

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

    RecipeOrderbook.Recipe NULL_RECIPE = RecipeOrderbookBase.Recipe(new bytes32[](0), new bytes[](0));

    function setUp() public {
        baseToken = new MockERC20("Base Token", "BT");
        baseToken2 = new MockERC20("Base Token2", "BT2");

        targetVault = new MockERC4626(baseToken);
        targetVault2 = new MockERC4626(baseToken);
        targetVault3 = new MockERC4626(baseToken);
        fundingVault = new MockERC4626(baseToken);
        fundingVault2 = new MockERC4626(baseToken2);

        recipeOrderbook = new MockRecipeOrderbook(
            address(weirollImplementation),
            initialProtocolFee,
            initialMinimumFrontendFee,
            OWNER_ADDRESS, // fee claimant
            address(pointsFactory)
        );

        vaultOrderbook = new VaultOrderbook();
    }

    function testBasicVaultOrderbookAllocate() public {
        vm.startPrank(USER01);
        baseToken.mint(USER01, 1000 * 1e18);
        baseToken.approve(address(vaultOrderbook), 300 * 1e18);
        baseToken.approve(address(fundingVault), 100 * 1e18);

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(baseToken);
        uint256[] memory tokenRatesRequested = new uint256[](1);
        tokenRatesRequested[0] = 1e18;

        uint256 order1Id =
            vaultOrderbook.createAPOrder(address(targetVault), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        uint256 order2Id =
            vaultOrderbook.createAPOrder(address(targetVault2), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        uint256 order3Id =
            vaultOrderbook.createAPOrder(address(targetVault3), address(0), 100 * 1e18, block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        VaultOrderbook.APOrder memory order1 =
            VaultOrderbook.APOrder(order1Id, address(targetVault), USER01, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultOrderbook.APOrder memory order2 =
            VaultOrderbook.APOrder(order2Id, address(targetVault2), USER01, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);
        VaultOrderbook.APOrder memory order3 =
            VaultOrderbook.APOrder(order3Id, address(targetVault3), USER01, address(0), block.timestamp + 1 days, tokensRequested, tokenRatesRequested);

        uint256[][] memory moreCampaignIds = new uint256[][](3);
        moreCampaignIds[0] = new uint256[](1);
        moreCampaignIds[0][0] = 0;
        moreCampaignIds[1] = new uint256[](1);
        moreCampaignIds[1][0] = 1;
        moreCampaignIds[2] = new uint256[](1);
        moreCampaignIds[2][0] = 2;
        VaultOrderbook.APOrder[] memory orders = new VaultOrderbook.APOrder[](3);

        bytes32 order1Hash = vaultOrderbook.getOrderHash(order1);
        bytes32 order2Hash = vaultOrderbook.getOrderHash(order2);
        bytes32 order3Hash = vaultOrderbook.getOrderHash(order3);

        orders[0] = order1;
        orders[1] = order2;
        orders[2] = order3;

        // Mock the previewRateAfterDeposit function
        vm.mockCall(
            address(targetVault), abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), uint256(100 * 1e18)), abi.encode(2e18)
        );
        vm.mockCall(
            address(targetVault2), abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), uint256(100 * 1e18)), abi.encode(2e18)
        );
        vm.mockCall(
            address(targetVault3), abi.encodeWithSelector(ERC4626i.previewRateAfterDeposit.selector, address(baseToken), uint256(100 * 1e18)), abi.encode(2e18)
        );

        uint256[] memory fillAmounts = new uint256[](3);
        fillAmounts[0] = type(uint256).max;
        fillAmounts[1] = type(uint256).max;
        fillAmounts[2] = type(uint256).max;
        vaultOrderbook.allocateOrders(orders, fillAmounts);

        //Verify none of the orders allocated
        assertEq(targetVault.balanceOf(USER01), 100 * 1e18);
        assertEq(targetVault2.balanceOf(USER01), 100 * 1e18);
        assertEq(targetVault3.balanceOf(USER01), 100 * 1e18);

        assertEq(vaultOrderbook.orderHashToRemainingQuantity(order1Hash), 0);
        assertEq(vaultOrderbook.orderHashToRemainingQuantity(order2Hash), 0);
        assertEq(vaultOrderbook.orderHashToRemainingQuantity(order3Hash), 0);

        assertEq(baseToken.balanceOf(address(USER01)), 1000 * 1e18 - 300 * 1e18);

        vm.stopPrank();
    }

    function testBasicRecipeOrderbookAllocate() public {
        uint256 frontendFee = recipeOrderbook.minimumFrontendFee();
        uint256 marketId = recipeOrderbook.createMarket(address(baseToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        vm.startPrank(USER02);
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(baseToken2);
        uint256[] memory tokenAmountsOffered = new uint256[](1);
        tokenAmountsOffered[0] = 1000e18;

        baseToken2.mint(USER02, 1000e18);
        baseToken2.approve(address(recipeOrderbook), 1000e18);

        uint256 orderId = recipeOrderbook.createIPOrder(
            marketId, // Referencing the created market
            orderAmount, // Total input token amount
            block.timestamp + 30 days, // Expiry time
            tokensOffered, // Incentive tokens offered
            tokenAmountsOffered // Incentive amounts offered
        );
        vm.stopPrank();

        // Mint liquidity tokens to the AP to fill the order
        baseToken.mint(USER01, fillAmount);
        vm.startPrank(USER01);
        baseToken.approve(address(recipeOrderbook), fillAmount);
        vm.stopPrank();

        // Fill the order
        vm.startPrank(USER01);
        recipeOrderbook.fillIPOrders(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeOrderbook.orderIDToIPOrder(orderId);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);
    }
}
