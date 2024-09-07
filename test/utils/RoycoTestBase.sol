// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../../../src/WeirollWallet.sol";
import "../../../src/RecipeOrderbook.sol";
import "../../../src/PointsFactory.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import "lib/forge-std/src/Test.sol";

contract RoycoTestBase is Test {
    // -----------------------------------------
    // Test Wallets
    // -----------------------------------------
    Vm.Wallet internal OWNER;
    address internal OWNER_ADDRESS;

    Vm.Wallet internal ALICE;
    Vm.Wallet internal BOB;
    Vm.Wallet internal CHARLIE;
    Vm.Wallet internal DAN;

    address internal ALICE_ADDRESS;
    address internal BOB_ADDRESS;
    address internal CHARLIE_ADDRESS;
    address internal DAN_ADDRESS;

    // -----------------------------------------
    // Royco Contracts
    // -----------------------------------------
    WeirollWallet public weirollImplementation;
    RecipeOrderbook public orderbook;
    MockERC20 public mockLiquidityToken;
    MockERC20 public mockIncentiveToken;
    MockERC4626 public mockVault;
    PointsFactory public pointsFactory;

    // -----------------------------------------
    // Modifiers
    // -----------------------------------------
    modifier prankModifier(address pranker) {
        vm.startPrank(pranker);
        _;
        vm.stopPrank();
    }

    // -----------------------------------------
    // Setup Functions
    // -----------------------------------------
    function setupBaseEnvironment() internal virtual {
        setupWallets();
        setUpRoycoContracts();
    }

    function initWallet(string memory name, uint256 amount) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory wallet = vm.createWallet(name);
        vm.label(wallet.addr, name);
        vm.deal(wallet.addr, amount);
        return wallet;
    }

    function setupWallets() internal {
        // Init wallets with 1000 ETH each
        OWNER = initWallet("OWNER", 1000 ether);
        ALICE = initWallet("ALICE", 1000 ether);
        BOB = initWallet("BOB", 1000 ether);
        CHARLIE = initWallet("CHARLIE", 1000 ether);
        DAN = initWallet("DAN", 1000 ether);

        // Set addresses
        OWNER_ADDRESS = OWNER.addr;
        ALICE_ADDRESS = ALICE.addr;
        BOB_ADDRESS = BOB.addr;
        CHARLIE_ADDRESS = CHARLIE.addr;
        DAN_ADDRESS = DAN.addr;
    }

    function setUpRoycoContracts() internal {
        weirollImplementation = new WeirollWallet();
        mockLiquidityToken = new MockERC20("Mock Liquidity Token", "MLT");
        mockIncentiveToken = new MockERC20("Mock Incentive Token", "MIT");
        mockVault = new MockERC4626(mockLiquidityToken);
        pointsFactory = new PointsFactory();
    }
}
