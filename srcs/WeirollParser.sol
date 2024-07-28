// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library WeirollParser {
    uint256 constant FLAG_CT_DELEGATECALL = 0x00;
    uint256 constant FLAG_CT_CALL = 0x01;
    uint256 constant FLAG_CT_STATICCALL = 0x02;
    uint256 constant FLAG_CT_VALUECALL = 0x03;
    uint256 constant FLAG_CT_MASK = 0x03;
    // uint256 constant FLAG_EXTENDED_COMMAND = 0x80;
    // uint256 constant FLAG_TUPLE_RETURN = 0x40;

    // uint256 constant SHORT_COMMAND_FILL = 0x000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    function getSelector(bytes32 command) public pure returns (bytes4) {
        return bytes4(command);
    }

    function getAddress(bytes32 command) public pure returns (address) {
        return address(uint160(uint256(command)));
    }

    function getFlags(bytes32 command) internal pure returns (uint256) {
        return uint256(uint8(bytes1(command << 32)));
    }

    function getCalltype(bytes32 command) public pure returns (uint256) {
        return getFlags(command) & FLAG_CT_MASK;
    }

    function isDelegatecall(bytes32 command) public pure returns (bool) {
        return getCalltype(command) == FLAG_CT_DELEGATECALL;
    }

    function isCall(bytes32 command) public pure returns (bool) {
        return getCalltype(command) == FLAG_CT_CALL;
    }

    function isStaticcall(bytes32 command) public pure returns (bool) {
        return getCalltype(command) == FLAG_CT_STATICCALL;
    }

    function isCallWithValue(bytes32 command) public pure returns (bool) {
        return getCalltype(command) == FLAG_CT_VALUECALL;
    }

    // ...
}
