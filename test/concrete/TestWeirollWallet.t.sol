// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { VM } from "lib/weiroll/contracts/VM.sol";
import { Clone } from "lib/clones-with-immutable-args/src/Clone.sol";
import "../../src/WeirollWallet.sol";
import { TestBase } from "../utils/TestBase.t.sol";

contract WeirollWalletTest is TestBase {
    function setUp() public {
        setupTestEnvironment();
    }
}
