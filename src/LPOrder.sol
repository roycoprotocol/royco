// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { VM } from "lib/weiroll/contracts/VM.sol";
import { Clone } from "lib/clones-with-immutable-args/src/Clone.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

/// @title OrderFactory
/// @author Royco
/// @notice LPOrder implementation contract.
///   Implements a simple LP order to supply an asset for a given action
contract LPOrder is Clone, VM {
    using SafeTransferLib for ERC20;
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    error NotOwner();
    error NotMarket();
    error WalletLocked();

    /// @notice Only the owner of the contract can call the function
    modifier onlyOwner() {
        if (msg.sender != owner()) {
            revert NotOwner();
        }
        _;
    }

    /// @notice Only the orderbook contract can call the function
    modifier onlyOrderbook() {
        if (msg.sender != orderbook()) {
            revert NotMarket();
        }
        _;
    }

    /// @notice The wallet cannot be locked
    modifier notLocked() {
        if (lockedUntil > block.timestamp) {
            revert WalletLocked();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /// @dev Whether or not this order has been executed
    bool public executed;
    uint256[] private _allowedMarkets;
    uint256[] private _desiredIncentives;

    function allowedMarkets() public view returns (uint256[] memory) {
        return _allowedMarkets;
    }

    function desiredIncentives() public view returns (uint256[] memory) {
        return _desiredIncentives;
    }

    /// @param markets The markets for which this order is valid
    function initialize(uint256[] calldata markets, uint256[] calldata _expectedIncentives) external onlyOrderbook {
        _allowedMarkets = markets;
        /// Allowlist all markets
        for (uint256 i; i < markets.length;) {
            supportedMarkets[markets[i]] = true;
            expectedIncentives[markets[i]] = _expectedIncentives[i];

            unchecked {
                ++i;
            }
        }
    }

    /// @param _marketId The market which the order was filled into
    function fillOrder(uint256 _marketId) external onlyOrderbook {
        marketId = _marketId;
    }

    /// @param newAddress The new address to sweep funds to
    /// @param amountToSweep The amount of tokens to transfer to the new address
    function fundSweepToNewOrder(address newAddress, uint256 amountToSweep) external onlyOrderbook {
        ERC20 _depositToken = depositToken();
        _depositToken.safeTransfer(newAddress, amountToSweep);
    }

    /*//////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public marketId;

    /// @notice The address of the order creator (owner)
    function owner() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// @notice The address of the orderbook exchange contract
    function orderbook() public pure returns (address) {
        return _getArgAddress(20);
    }

    /// @notice The deposit token being LP'ed
    function depositToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(40));
    }

    /// @notice The amount of tokens to be LP'ed
    function amount() public pure returns (uint256) {
        return _getArgUint256(60);
    }

    /// @notice The max duration to lock for
    function maxDuration() public pure returns (uint256) {
        return _getArgUint256(92);
    }

    /// @notice Whether or not a market is supported by this order
    mapping(uint256 marketId => bool) public supportedMarkets;
    /// @notice Mappiing to determine how much incentives are wanted for a market
    mapping(uint256 marketId => uint256 incentives) public expectedIncentives;
    /*//////////////////////////////////////////////////////////////
                               LOCKING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The time until the wallet is locked.
    uint256 public lockedUntil;

    /// @notice Lock the wallet until a certain time.
    function lockWallet(uint256 unlockTime) public onlyOrderbook {
        lockedUntil = unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                            CANCELLATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The order has been cancelled.
    bool public cancelled;

    /// @notice Cancel the order.
    ///   We only support cancelling through the OrderBook in order to ensure all funds are exited properly
    function cancel() public onlyOrderbook {
        // Mark the order as cancelled.
        cancelled = true;
    }

    /*//////////////////////////////////////////////////////////////
                               EXECUTION LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Execute the Weiroll VM with the given commands.
    /// @param commands The commands to be executed by the Weiroll VM.
    function executeWeiroll(bytes32[] calldata commands, bytes[] calldata state) public payable onlyOrderbook returns (bytes[] memory) {
        require(!executed, "Royco: AlreadyRan");

        executed = true;
        // Execute the Weiroll VM.
        return _execute(commands, state);
    }

    /// @notice Execute the Weiroll VM with the given commands.
    /// @param commands The commands to be executed by the Weiroll VM.
    function manualExecuteWeiroll(bytes32[] calldata commands, bytes[] calldata state) public payable onlyOwner notLocked returns (bytes[] memory) {
        // Prevent people from approving w/e then rugging during vesting
        require(executed, "Royco: Order unfilled");
        // Execute the Weiroll VM.
        return _execute(commands, state);
    }

    /// @notice Execute a generic call to another contract.
    /// @param to The address to call
    /// @param value The ether value of the execution
    /// @param data The data to pass along with the call
    function execute(address to, uint256 value, bytes memory data) public onlyOwner notLocked returns (bytes memory) {
        // Prevent people from approving w/e then rugging during vesting
        require(executed, "Royco: Order unfilled");
        // Execute the call.
        (bool success, bytes memory result) = to.call{ value: value }(data);
        if (!success) {
            revert("Generic execute proxy failed"); //TODO: Better revert message (stringify result?)
        }
        return result;
    }
}
