pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ExperimentBnbBusdLpToken is ERC20 {
    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor() public ERC20("Experiment BNB BUSD LP Token", "EBL") {
        _mint(address(this), 1000000 * (10**uint256(decimals())));
        _approve(address(this), msg.sender, totalSupply());
    }
}
