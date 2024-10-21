/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IERC1271
/// @notice Interface defined by EIP-1271
/// @dev Interface for verifying contract account signatures
interface IERC1271 {
    /// @notice Returns whether the provided signature is valid for the provided data
    /// @dev Returns 0x1626ba7e (magic value) when function passes.
    /// @param digest Hash of the message to validate the signature against
    /// @param signature Signature produced for the provided digest
    function isValidSignature(bytes32 digest, bytes memory signature) external view returns (bytes4);
}
