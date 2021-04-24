// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract TollERC20 is ERC20Burnable, ERC20Pausable, ERC20Mintable, ERC20Detailed {
    constructor () public ERC20Detailed("Toll Free Swap", "TOLL", 18) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
