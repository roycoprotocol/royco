// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ClonesWithImmutableArgs} from "../../../lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";

/// @title OrderFactory
/// @author Royco
/// @notice Factory contract for creating orders
contract OrderFactory {
    using ClonesWithImmutableArgs for address;

    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    // Implementation contract address
    address public orderImplementation;

    /// @notice Deploy a proxy for the order implementation contract
    // todo: MORE NEEDS TO BE DONE HERE FOR DIFFERENTIATING BETWEEN ACTION ORDERS AND REWARD ORDERS
    function deployClone(address owner, address market, uint256 side) internal returns (address clone) {
        // Pack the data to be passed to the implementation contract.
        bytes memory data = abi.encodePacked(owner, market, side);

        // Deploy the clone.
        clone = orderImplementation.clone(data);
    }
}
