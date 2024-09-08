// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/libraries/SafeCast.sol";

contract SafeCastTest is Test {
    using SafeCast for uint256;
    using SafeCast for int256;

    function testToUint128(uint256 value) public {
        if (value <= type(uint128).max) {
            assertEq(value.toUint128(), uint128(value));
        } else {
            vm.expectRevert();
            value.toUint128();
        }
    }

    function testToUint96(uint256 value) public {
        if (value <= type(uint96).max) {
            assertEq(value.toUint96(), uint96(value));
        } else {
            vm.expectRevert();
            value.toUint96();
        }
    }

    function testToUint64(uint256 value) public {
        if (value <= type(uint64).max) {
            assertEq(value.toUint64(), uint64(value));
        } else {
            vm.expectRevert();
            value.toUint64();
        }
    }

    function testToUint32(uint256 value) public {
        if (value <= type(uint32).max) {
            assertEq(value.toUint32(), uint32(value));
        } else {
            vm.expectRevert();
            value.toUint32();
        }
    }

    function testToUint160(uint256 value) public {
        if (value <= type(uint160).max) {
            assertEq(value.toUint160(), uint160(value));
        } else {
            vm.expectRevert();
            value.toUint160();
        }
    }

    function testToInt128(int256 value) public {
        if (value >= type(int128).min && value <= type(int128).max) {
            assertEq(value.toInt128(), int128(value));
        } else {
            vm.expectRevert();
            value.toInt128();
        }
    }

    function testToInt256(uint256 value) public {
        if (value < 2 ** 255) {
            assertEq(value.toInt256(), int256(value));
        } else {
            vm.expectRevert();
            value.toInt256();
        }
    }

    function testFuzzToUint128(uint256 value) public {
        vm.assume(value <= type(uint128).max);
        assertEq(value.toUint128(), uint128(value));
    }

    function testFuzzToUint96(uint256 value) public {
        vm.assume(value <= type(uint96).max);
        assertEq(value.toUint96(), uint96(value));
    }

    function testFuzzToUint64(uint256 value) public {
        vm.assume(value <= type(uint64).max);
        assertEq(value.toUint64(), uint64(value));
    }

    function testFuzzToUint32(uint256 value) public {
        vm.assume(value <= type(uint32).max);
        assertEq(value.toUint32(), uint32(value));
    }

    function testFuzzToUint160(uint256 value) public {
        vm.assume(value <= type(uint160).max);
        assertEq(value.toUint160(), uint160(value));
    }

    function testFuzzToInt128(int256 value) public {
        vm.assume(value >= type(int128).min && value <= type(int128).max);
        assertEq(value.toInt128(), int128(value));
    }

    function testFuzzToInt256(uint256 value) public {
        vm.assume(value < 2 ** 255);
        assertEq(value.toInt256(), int256(value));
    }
}
