pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ExperimentBnbToken is ERC20 {
    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor() public ERC20("Experiment BNB Token", "EBN") {
        _mint(address(this), 1000000 * (10**uint256(decimals())));
        _approve(address(this), msg.sender, totalSupply());
    }
}
