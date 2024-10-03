// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../../../src/WeirollWallet.sol";
import "test/mocks/MockRecipeKernel.sol";
import "../../../src/PointsFactory.sol";
import { WrappedVaultFactory } from "../../../src/WrappedVaultFactory.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Vm.sol";

contract RoycoTestBase is Test {
    // -----------------------------------------
    // Test Wallets
    // -----------------------------------------
    Vm.Wallet internal OWNER;
    address internal OWNER_ADDRESS;

    Vm.Wallet internal POINTS_FACTORY_OWNER;
    address internal POINTS_FACTORY_OWNER_ADDRESS;

    Vm.Wallet internal ALICE;
    Vm.Wallet internal BOB;
    Vm.Wallet internal CHARLIE;
    Vm.Wallet internal DAN;

    address internal ALICE_ADDRESS;
    address internal BOB_ADDRESS;
    address internal CHARLIE_ADDRESS;
    address internal DAN_ADDRESS;

    uint256 internal constant ERC4626I_FACTORY_PROTOCOL_FEE = 0.01e18;
    uint256 internal constant ERC4626I_FACTORY_MIN_FRONTEND_FEE = 0.02e18;

    // -----------------------------------------
    // Royco Contracts
    // -----------------------------------------
    WeirollWallet public weirollImplementation;
    MockRecipeKernel public recipeKernel;
    MockERC20 public mockLiquidityToken;
    MockERC20 public mockIncentiveToken;
    MockERC4626 public mockVault;
    PointsFactory public pointsFactory;
    WrappedVaultFactory public erc4626iFactory;

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
        POINTS_FACTORY_OWNER = initWallet("POINTS_FACTORY_OWNER", 1000 ether);
        ALICE = initWallet("ALICE", 1000 ether);
        BOB = initWallet("BOB", 1000 ether);
        CHARLIE = initWallet("CHARLIE", 1000 ether);
        DAN = initWallet("DAN", 1000 ether);

        // Set addresses
        OWNER_ADDRESS = OWNER.addr;
        POINTS_FACTORY_OWNER_ADDRESS = POINTS_FACTORY_OWNER.addr;
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
        pointsFactory = new PointsFactory(POINTS_FACTORY_OWNER_ADDRESS);
        erc4626iFactory = new WrappedVaultFactory(OWNER_ADDRESS, ERC4626I_FACTORY_PROTOCOL_FEE, ERC4626I_FACTORY_MIN_FRONTEND_FEE, address(pointsFactory));
    }
}
