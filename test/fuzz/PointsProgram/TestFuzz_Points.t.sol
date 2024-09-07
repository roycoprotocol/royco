// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/Points.sol";
import "../../../src/PointsFactory.sol";
import { ERC4626i, ERC4626 } from "../../../src/ERC4626i.sol";
import { Ownable } from "lib/solady/src/auth/Ownable.sol";
import { RoycoTestBase } from "../../utils/RoycoTestBase.sol";

contract TestFuzz_Points is RoycoTestBase {

    function setUp() external {
        setupBaseEnvironment();
    }

}
