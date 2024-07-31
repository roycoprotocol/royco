// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

contract Points {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public immutable decimals;

    constructor(string memory _name, string memory _symbol) {
      name = _name;
      symbol = _symbol;
      decimals = 18;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool success) {
        success = true;
        emit Transfer(msg.sender, to, amount);
    }
}
