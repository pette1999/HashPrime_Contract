// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8) ERC20(_name, _symbol) {
        _mint(msg.sender, 1000000000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
