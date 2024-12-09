// SPDX-Liense-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";

import { WrappedVault } from "src/WrappedVault.sol";
import { WrappedVaultFactory } from "src/WrappedVaultFactory.sol";

import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { Ownable2Step, Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

import { PointsFactory } from "src/PointsFactory.sol";
import { Ownable as SoladyOwnable } from "lib/solady/src/auth/Ownable.sol";

import { Test, console } from "forge-std/Test.sol";

contract WrappedVaultTest is Test {
    using FixedPointMathLib for *;

    WrappedVaultFactory testFactory;
    uint256 mainnetFork;
    address owner = 0x85De42e5697D16b853eA24259C42290DaCe35190;

    function setUp() public {
        mainnetFork = vm.createFork("https://gateway.tenderly.co/public/mainnet");
        vm.selectFork(mainnetFork);

        testFactory = WrappedVaultFactory(0x75E502644284eDf34421f9c355D75DB79e343Bca);
    }

    function testTetherVault() external {
        address wvi = address(new WrappedVault());

        vm.startPrank(owner);
        testFactory.updateWrappedVaultImplementation(wvi);
        vm.stopPrank();

        testFactory.wrapVault(ERC4626(0x5C20B550819128074FD538Edf79791733ccEdd18), 0x9FC3da866e7DF3a1c57adE1a97c9f00a70f010c8, "Test123", 5_000_000_000_000_000);
    }
}
