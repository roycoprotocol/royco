// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { MockERC20, ERC20 } from "test/mocks/MockERC20.sol";

import { LPOrder } from "src/LPOrder.sol";
import { Orderbook } from "src/Orderbook.sol";

import { console } from "forge-std/console.sol";

contract RoycoBaseTest is Test {
    Orderbook public book;
    LPOrder public ORDER_IMPL = new LPOrder();

    address User01 = address(0x07);

    MockERC20 public rewardToken = new MockERC20("Reward Token", "REWARD");
    MockERC20 public depositToken = new MockERC20("Deposit Token", "DEPOSIT");

    function setUp() public {
        book = new Orderbook(address(ORDER_IMPL));
    }

    /*//////////////////////////////////////////////////////////////
                              BASIC TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanCreateMarket() public {
        // bytes32[] literal
        bytes32[] memory commands = new bytes32[](1);
        // bytes[] literal
        bytes[] memory state = new bytes[](1);

        Orderbook.Recipe memory enter = Orderbook.Recipe({ weirollCommands: commands, weirollState: state });

        Orderbook.Recipe memory exit = Orderbook.Recipe({ weirollCommands: commands, weirollState: state });

        uint256 firstMarketId = book.createMarket(depositToken, rewardToken, Orderbook.MarketType.FL_Vesting, enter, exit);
        assertEq(firstMarketId, 1);
        uint256 secondMarketId = book.createMarket(depositToken, rewardToken, Orderbook.MarketType.FL_Vesting, enter, exit);
        assertEq(firstMarketId + 1, secondMarketId);

        (ERC20 _depositToken, ERC20 _primaryRewardToken, Orderbook.MarketType _type,,) = book.markets(firstMarketId);

        assertEq(address(_depositToken), address(depositToken));
        assertEq(address(_primaryRewardToken), address(rewardToken));
        assertEq(uint8(_type), uint8(Orderbook.MarketType.FL_Vesting));
    }

    function testPostLPAsk() public {
        // bytes32[] literal
        bytes32[] memory commands = new bytes32[](1);
        // bytes[] literal
        bytes[] memory state = new bytes[](1);

        Orderbook.Recipe memory enter = Orderbook.Recipe({ weirollCommands: commands, weirollState: state });

        Orderbook.Recipe memory exit = Orderbook.Recipe({ weirollCommands: commands, weirollState: state });

        uint256 marketId = book.createMarket(depositToken, rewardToken, Orderbook.MarketType.FL_Vesting, enter, exit);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;

        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        (LPOrder order, uint256 orderId) = book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);

        /// Should be uninitialized
        assertEq(order.marketId(), 0);
        assertEq(order.owner(), address(this));
        assertEq(order.orderbook(), address(book));
        assertEq(address(order.depositToken()), address(depositToken));
        assertEq(order.amount(), 100 ether);
        assertEq(order.maxDuration(), 10 days);
        assertEq(order.expectedIncentives(marketId), 1 ether);

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);
        (, uint256 orderId2) = book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);

        assertEq(orderId + 1, orderId2);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);

        allowedMarkets = new uint256[](5);

        vm.expectRevert("Royco: Length Mismatch");
        book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);
    }

    function testPostIPAsk() public {
        // bytes32[] literal
        bytes32[] memory commands = new bytes32[](1);
        // bytes[] literal
        bytes[] memory state = new bytes[](1);

        Orderbook.Recipe memory enter = Orderbook.Recipe({ weirollCommands: commands, weirollState: state });

        Orderbook.Recipe memory exit = Orderbook.Recipe({ weirollCommands: commands, weirollState: state });

        uint256 marketId = book.createMarket(depositToken, rewardToken, Orderbook.MarketType.FL_Vesting, enter, exit);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);

        uint256 IPOrderId = book.createIPOrder(10 days, 100 ether, 1 ether, uint128(marketId), 0, type(uint96).max);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);
        uint256 IPOrderId2 = book.createIPOrder(10 days, 100 ether, 1 ether, uint128(marketId), 0, type(uint96).max);

        assertEq(IPOrderId + 1, IPOrderId2);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        book.createIPOrder(10 days, 100 ether, 1 ether, uint128(marketId), 0, type(uint96).max);
    }

    function testBasicFillOrder() public {
        // bytes32[] literal
        bytes32[] memory enterCommands = new bytes32[](2);
        enterCommands[0] = 0x095ea7b3010001ffffffffff32b62298fdd99c2be9d59dc93f5efd6cf5c2edb3;
        enterCommands[1] = 0x39dc5ef201020304ffffffff3cea719b30456e2f6877c2d449c91f7b15a9436b;
        // bytes[] literal
        bytes[] memory enterState = new bytes[](5);
        enterState[0] = hex"0000000000000000000000003cea719b30456e2f6877c2d449c91f7b15a9436b";
        enterState[1] = hex"000000000000000000000000000000000000000000000000000000000098967f";
        enterState[2] = hex"00000000000000000000000032b62298fdd99c2be9d59dc93f5efd6cf5c2edb3";
        enterState[3] = hex"000000000000000000000000ccb9ea6171e0d166bbed847ae0b532521bb826f5";
        enterState[4] = hex"000000000000000000000000000000000000000000000000000000000000000a";

        Orderbook.Recipe memory enter = Orderbook.Recipe({ weirollCommands: enterCommands, weirollState: enterState });

        Orderbook.Recipe memory exit = Orderbook.Recipe({ weirollCommands: enterCommands, weirollState: enterState });

        uint256 marketId = book.createMarket(depositToken, rewardToken, Orderbook.MarketType.BL_Vesting, enter, exit);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);

        uint256 IPOrderId = book.createIPOrder(10 days, 100 ether, 1 ether, uint128(marketId), 0, type(uint96).max);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;

        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        (, uint256 orderId) = book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);

        book.matchOrders(IPOrderId, orderId);
    }

    function createSimpleMarket(Orderbook.MarketType _type) public returns (uint256 marketId) {
        // bytes32[] literal
        bytes32[] memory enterCommands = new bytes32[](2);
        enterCommands[0] = 0x095ea7b3010001ffffffffff32b62298fdd99c2be9d59dc93f5efd6cf5c2edb3;
        enterCommands[1] = 0x39dc5ef201020304ffffffff3cea719b30456e2f6877c2d449c91f7b15a9436b;
        // bytes[] literal
        bytes[] memory enterState = new bytes[](5);
        enterState[0] = hex"0000000000000000000000003cea719b30456e2f6877c2d449c91f7b15a9436b";
        enterState[1] = hex"000000000000000000000000000000000000000000000000000000000098967f";
        enterState[2] = hex"00000000000000000000000032b62298fdd99c2be9d59dc93f5efd6cf5c2edb3";
        enterState[3] = hex"000000000000000000000000ccb9ea6171e0d166bbed847ae0b532521bb826f5";
        enterState[4] = hex"000000000000000000000000000000000000000000000000000000000000000a";

        Orderbook.Recipe memory enter = Orderbook.Recipe({ weirollCommands: enterCommands, weirollState: enterState });

        Orderbook.Recipe memory exit = Orderbook.Recipe({ weirollCommands: enterCommands, weirollState: enterState });

        marketId = book.createMarket(depositToken, rewardToken, _type, enter, exit);
    }

    function testCreateLPOrderAndFill() public {
        uint256 marketId = createSimpleMarket(Orderbook.MarketType.FL_Vesting);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);
        uint256 IPOrderId = book.createIPOrder(10 days, 100 ether, 1 ether, uint128(marketId), 0, type(uint96).max);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;

        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        uint256 initialTicketAmount = book.nextLPOrderId();
        book.createLPOrderAndFill(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, IPOrderId);
        assertEq(initialTicketAmount + 1, book.nextLPOrderId());
    }

    function testCreateIPOrderAndFill() public {
        uint256 marketId = createSimpleMarket(Orderbook.MarketType.FL_Vesting);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;

        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        (LPOrder order, uint256 orderId) = book.createLPOrder(depositToken, 100 ether, 0, desiredIncentives, allowedMarkets, type(uint96).max);

        uint256 initialTicketAmount = book.nextIPOrderId();
        uint256 initialRewardBalance = rewardToken.balanceOf(address(this));
        
        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);
        book.createIPOrderAndFill(0, 100 ether, 1 ether, uint128(marketId), 0, orderId);

        assertEq(initialTicketAmount + 1, book.nextIPOrderId());
        assertGt(rewardToken.balanceOf(address(this)), initialRewardBalance);
        assertEq(order.lockedUntil(), 1);
    }

    function testCancelIPOrder() public {
        uint256 marketId = createSimpleMarket(Orderbook.MarketType.FL_Vesting);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);
        uint256 IPOrderId = book.createIPOrder(10 days, 100 ether, 1 ether, uint128(marketId), 0, type(uint96).max);

        // Cannot cancel order that doesn't exist
        vm.expectRevert("Royco: Not Owner");
        book.cancelIPOrder(IPOrderId + 1);

        vm.startPrank(vm.addr(0xb44f));
        vm.expectRevert("Royco: Not Owner");
        book.cancelIPOrder(IPOrderId);
        vm.stopPrank();

        {
            vm.startPrank(User01);
            uint256[] memory allowedMarkets = new uint256[](1);
            allowedMarkets[0] = marketId;

            uint256[] memory desiredIncentives = new uint256[](1);
            desiredIncentives[0] = 1 ether;

            depositToken.mint(User01, 50 ether);
            depositToken.approve(address(book), 50 ether);

            book.createLPOrderAndFill(depositToken, 50 ether, 10 days, desiredIncentives, allowedMarkets, IPOrderId);
            vm.stopPrank();
        }

        // Cannot rug already paid out incentives
        // and incentives return to the IP
        book.cancelIPOrder(IPOrderId);
        assertEq(rewardToken.balanceOf(User01), 50 ether);
        assertEq(rewardToken.balanceOf(address(this)), 50 ether);
    }

    function testCancelUnfufilledLPOrder() public {
        uint256 marketId = createSimpleMarket(Orderbook.MarketType.FL_Vesting);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);
        book.createIPOrder(10 days, 100 ether, 1 ether, uint128(marketId), 0, type(uint96).max);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;
        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        // Can't cancel an order that doesn't exist
        vm.expectRevert();
        book.cancelUnfufilledLPOrder(5);

        (, uint256 orderId) = book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);

        // Can't cancel someone else's order
        vm.startPrank(User01);
        vm.expectRevert("Royco: Not Owner");
        book.cancelUnfufilledLPOrder(orderId);
        vm.stopPrank();

        book.cancelUnfufilledLPOrder(orderId);

        assertEq(book.LpOrders(orderId).expiry(), 0);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);

        vm.expectRevert("Royco: Order Expired");
        book.createIPOrderAndFill(0, 100 ether, 1 ether, uint128(marketId), 10 days, orderId);
    }

    function testClaimRewards() public {
        uint256 marketId = createSimpleMarket(Orderbook.MarketType.BL_Vesting);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;
        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        (, uint256 orderId) = book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);

        book.createIPOrderAndFill(0, 100 ether, 1 ether, uint128(marketId), 10 days, orderId);

        vm.expectRevert("Royco: Rewards Not Unlocked");
        book.claimRewards(rewardToken, orderId);

        vm.warp(11 days);

        vm.startPrank(User01);
        vm.expectRevert("Royco: Not Owner");
        book.claimRewards(rewardToken, orderId);
        vm.stopPrank();

        uint256 initialBalance = rewardToken.balanceOf(address(this));
        book.claimRewards(rewardToken, orderId);
        assertGt(rewardToken.balanceOf(address(this)), initialBalance);
    }

    function testCancelFufilledLPOrder() public {
        uint256 marketId = createSimpleMarket(Orderbook.MarketType.Forfeitable_Vested);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;

        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        (, uint256 orderId) = book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);
        book.createIPOrderAndFill(0, 100 ether, 1 ether, uint128(marketId), 10 days, orderId);

        book.cancelLPOrder(orderId);
    }

    function testCanCreateIPOrderWithUnlockTime() public {
        uint256 marketId = createSimpleMarket(Orderbook.MarketType.FL_Vesting);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;

        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        vm.warp(3 days);

        (LPOrder order, uint256 orderId) = book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);
        book.createIPOrderAndFill(0, 100 ether, 1 ether, uint128(marketId), 10 days, orderId);

        // Should be locked until time, not time + duration
        assertEq(order.lockedUntil(), 10 days);
    }

    function testStreamingMarketPayoff() public {
        uint256 marketId = createSimpleMarket(Orderbook.MarketType.Streaming);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);
        book.createIPOrder(10 days, 100 ether, 1 ether, uint128(marketId), 0, type(uint96).max);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;
        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        (, uint256 orderId) = book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, type(uint96).max);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);
        book.createIPOrderAndFill(10 days, 100 ether, 1 ether, uint128(marketId), 0, orderId);

        vm.warp(5 days);

        uint256 amountReleased = book.releaseVestedTokens(1);
        assertApproxEqAbs(amountReleased, 50 ether, 0.001 ether);
    }

    function testCannotFufillExpiredOrder() public {
        uint256 marketId = createSimpleMarket(Orderbook.MarketType.Streaming);

        uint256[] memory allowedMarkets = new uint256[](1);
        allowedMarkets[0] = marketId;

        uint256[] memory desiredIncentives = new uint256[](1);
        desiredIncentives[0] = 1 ether;

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(book), 100 ether);

        (, uint256 orderId) = book.createLPOrder(depositToken, 100 ether, 10 days, desiredIncentives, allowedMarkets, 0);

        rewardToken.mint(address(this), 100 ether);
        rewardToken.approve(address(book), 100 ether);

        vm.expectRevert("Royco: Order Expired");
        book.createIPOrderAndFill(10 days, 100 ether, 1 ether, uint128(marketId), 0, orderId);
    }
}
