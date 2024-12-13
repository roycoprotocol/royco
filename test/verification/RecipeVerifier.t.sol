// SPDX-Liense-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { RecipeMarketHub, ERC20, RecipeMarketHubTestBase } from "../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { console2 } from "../../lib/forge-std/src/console2.sol";

contract RecipeVerifier is RecipeMarketHubTestBase {
    string constant MAINNET_RPC_URL = "https://mainnet.gateway.tenderly.co";
    string constant ARBITRUM_RPC_URL = "https://arbitrum.gateway.tenderly.co";
    string constant BASE_RPC_URL = "https://base.gateway.tenderly.co";
    string constant ETH_SEPOLIA_RPC_URL = "https://sepolia.gateway.tenderly.co";

    RecipeMarketHub RECIPE_MARKET_HUB;
    bytes32 MARKET_HASH;
    uint256 fork;

    function setUp() public {
        RECIPE_MARKET_HUB = RecipeMarketHub(0x783251f103555068c1E9D755f69458f39eD937c0);

        // Replace this with whatever network the Royco Recipe IAM was created on
        fork = vm.createFork(MAINNET_RPC_URL);

        // Replace this with the market hash of the market you are trying to verify
        MARKET_HASH = 0x83c459782b2ff36629401b1a592354fc085f29ae00cf97b803f73cac464d389b;
    }

    function test_RecipeMarketVerification(uint256 offerAmount, uint256 numDepositors) external {
        // Bound the number of depositors and offer amount to prevent overflows and underflows
        numDepositors = bound(numDepositors, 1, 100_000);

        vm.selectFork(fork);

        console2.log("Verifying Market...");

        // Get the token to deposit for this market
        (, ERC20 marketInputToken, uint256 lockupTime,,,,) = RECIPE_MARKET_HUB.marketHashToWeirollMarket(MARKET_HASH);

        offerAmount = bound(offerAmount, 1 * (10 ** (marketInputToken.decimals())), 100_000_000 * (10 ** (marketInputToken.decimals())));

        // Create an IP offer in the market
        address[] memory incentives = new address[](0);
        uint256[] memory incentiveAmounts = new uint256[](0);
        bytes32 ipOfferHash = RECIPE_MARKET_HUB.createIPOffer(MARKET_HASH, offerAmount, 0, incentives, incentiveAmounts);

        // Fill the IP Offer
        address[] memory aps = new address[](numDepositors);
        uint256[] memory fillAmounts = new uint256[](numDepositors);
        address[] memory weirollWallets = new address[](numDepositors);

        bytes32[] memory ipOfferHashes = new bytes32[](1);
        ipOfferHashes[0] = ipOfferHash;
        uint256[] memory depositorFillAmounts = new uint256[](1);

        // Distribute fill amounts based on random amounts
        for (uint256 i = 0; i < numDepositors; i++) {
            (address ap,) = makeAddrAndKey(string(abi.encode(i)));

            uint256 fillAmount = offerAmount / numDepositors;
            if (i == (numDepositors - 1)) {
                fillAmount = offerAmount - (fillAmount * (numDepositors - 1));
            }
            fillAmounts[i] = fillAmount;

            // Fund the AP and handle approval
            deal(address(marketInputToken), ap, fillAmounts[i]);
            vm.startPrank(ap);
            marketInputToken.approve(address(RECIPE_MARKET_HUB), fillAmounts[i]);

            depositorFillAmounts[0] = fillAmounts[i];
            // Record the logs to capture Transfer events
            vm.recordLogs();
            // AP Fills the offer (no funding vault)
            RECIPE_MARKET_HUB.fillIPOffers(ipOfferHashes, depositorFillAmounts, address(0), address(0xbeef));
            vm.stopPrank();

            // Extract the Weiroll wallet address
            weirollWallets[i] = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));
        }

        // Time travel to when the deposits are withdrawable
        vm.warp(block.timestamp + lockupTime);

        for (uint256 i = 0; i < numDepositors; ++i) {
            vm.warp(block.timestamp + (i * 30 minutes));

            uint256 preWithdrawApTokenBalance = ERC20(marketInputToken).balanceOf(aps[i]);
            uint256 preWithdrawWalletTokenBalance = ERC20(marketInputToken).balanceOf(weirollWallets[i]);

            vm.startPrank(aps[i]);
            RECIPE_MARKET_HUB.executeWithdrawalScript(weirollWallets[i]);
            vm.stopPrank();

            uint256 postWithdrawApTokenBalance = ERC20(marketInputToken).balanceOf(aps[i]);
            uint256 postWithdrawWalletTokenBalance = ERC20(marketInputToken).balanceOf(weirollWallets[i]);

            uint256 apBalanceChange = postWithdrawApTokenBalance - preWithdrawApTokenBalance;
            uint256 walletBalanceChange = postWithdrawWalletTokenBalance - preWithdrawWalletTokenBalance;

            // If the AP saw the expected increase, assert that first.
            // Otherwise, assert that the wallet saw the expected increase.
            if (apBalanceChange >= fillAmounts[i]) {
                assertGe(apBalanceChange, fillAmounts[i]);
            } else {
                assertGe(walletBalanceChange, fillAmounts[i]);
            }
        }

        console2.log("Market Successfully Verified.");
    }
}
