// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract Points {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    // event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public immutable decimals;

    address public immutable owner;

    constructor(string memory _name, string memory _symbol, address _owner) {
        name = _name;
        symbol = _symbol;
        decimals = 18;
        owner = _owner;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool success) {
        require(msg.sender == owner, "UNAUTHORIZED");
        success = true;
        emit Transfer(msg.sender, to, amount);
    }
}
