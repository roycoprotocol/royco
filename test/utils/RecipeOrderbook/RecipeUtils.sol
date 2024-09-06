// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../../..//src/RecipeOrderbook.sol";

contract RecipeUtils {
    // Recipe with no commands and state
    RecipeOrderbook.Recipe NULL_RECIPE = RecipeOrderbook.Recipe(new bytes32[](0), new bytes[](0));

    // Helper function to generate a random Recipe
    function generateRandomRecipe(uint256 commandCount, uint256 stateCount) public view returns (RecipeOrderbook.Recipe memory) {
        bytes32[] memory commands = new bytes32[](commandCount);
        bytes[] memory state = new bytes[](stateCount);

        for (uint256 i = 0; i < commandCount; i++) {
            commands[i] = generateRandomCommand();
        }

        for (uint256 i = 0; i < stateCount; i++) {
            state[i] = generateRandomState();
        }

        return RecipeOrderbook.Recipe(commands, state);
    }

    // Generate a random command (bytes32) for the weiroll VM
    function generateRandomCommand() internal view returns (bytes32) {
        bytes32 command;
        command = bytes32(blockhash(block.number - 1));
        return command;
    }

    // Generate random state (bytes) for the weiroll VM
    function generateRandomState() internal view returns (bytes memory) {
        // Create random length between 0 and 128 bytes
        uint256 length = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 129);
        bytes memory randomState = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            randomState[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(block.timestamp, i))) % 256));
        }

        return randomState;
    }
}
