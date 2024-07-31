// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

import { LPOrder } from "src/LPOrder.sol";
import { Orderbook } from "src/Orderbook.sol";

contract RoycoBaseTest is Test {
    Orderbook public book;
    LPOrder public order = new LPOrder();

    MockERC20 public rewardToken = new MockERC20("Reward Token", "REWARD");
    MockERC20 public depositToken = new MockERC20("Deposit Token", "DEPOSIT");

    function setUp() public {
        book = new Orderbook(address(order));
    }

    function testCanCreateMarket() public {
        // bytes32[] literal
        bytes32[] memory commands = new bytes32[](1);
        // bytes[] literal
        bytes[] memory state = new bytes[](1);

        Orderbook.Recipe memory enter = Orderbook.Recipe({ weirollCommands: commands, weirollState: state });

        Orderbook.Recipe memory exit = Orderbook.Recipe({ weirollCommands: commands, weirollState: state });

        book.createMarket(depositToken, rewardToken, Orderbook.MarketType.FL_Vesting, enter, exit);
    }

    function testPostLPAsk() public { }

    function testPostIPAsk() public { }
}
