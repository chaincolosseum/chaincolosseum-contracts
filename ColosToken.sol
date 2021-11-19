// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SkillToken.sol";

contract ColosToken is ERC20, ERC20Burnable, Ownable {
    using SafeMath for uint256;

    SkillToken public skill;
    address public game;

    constructor () public ERC20("ChainColosseum Token", "COLOS") {
        _mint(address(this), 1000000 * (10 ** uint256(decimals())));
        _approve(address(this), msg.sender, totalSupply());
    }

    /*
     * @dev Throws if called by any account other than the owner or game or skill
     */
    modifier onlyOwnerOrGameOrSkill() {
        require(isOwner() || isGame() || isSkill(), "caller is not the owner or game or skill");
        _;
    }

    /**
     * @dev Returns true if the caller is the current owner.
     */
    function isOwner() public view returns (bool) {
        return msg.sender == owner();
    }

    /**
     * @dev Returns true if the caller is skill contracts.
     */
    function isSkill() internal view returns (bool) {
        return msg.sender == address(skill);
    }

    function setupSkill(SkillToken _skill) external onlyOwner{
        skill = _skill;
    }

    /**
     * @dev Returns true if the caller is game contracts.
     */
    function isGame() internal view returns (bool) {
        return msg.sender == address(game);
    }

    function setupGame(address _game) external onlyOwner{
        game = _game;
    }

    /* Allow use to exchange (swap) their colos to skill */
    function swapToSkill(uint256 _amount) external {
        require(_amount > 0, "amount 0");
        address _from = msg.sender;
        uint256 skillAmount = _swapSkillAmount( _from, _amount);
        // holdersInfo[_from].avgTransactionBlock = _getAvgTransactionBlock(_from, holdersInfo[_from], _amount, true);
        super._burn(_from, _amount);
        skill.mint(_from, skillAmount);
    }

    function previewSwapSkillExpectedAmount(address _holderAddress, uint256 _colosAmount) external view returns (uint256 expectedSkill){
        return _swapSkillAmount( _holderAddress, _colosAmount);
    }

    function _swapSkillAmount(address _holderAddress, uint256 _colosAmount) internal view returns (uint256 expectedSkill){
        require(balanceOf(_holderAddress) >= _colosAmount, "Not enough COLOS");
        // uint256 penalty = getPenaltyPercent(_holderAddress);
        // if(penalty == 0){
        //     return _colosAmount;
        // }

        // return _colosAmount.sub(_colosAmount.mul(penalty).div(1e12));
        return _colosAmount;
    }


    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterColosseum).
    function mint(address _to, uint256 _amount) external virtual onlyOwnerOrGameOrSkill  {
        _mint(_to, _amount);
    }


    /// @dev overrides transfer function to meet tokenomics of COLOS
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        require(amount > 0, "amount 0");
        if (recipient == 0x000000000000000000000000000000000000dEaD) {
            super._burn(sender, amount);
        } else {
            // 5% of every transfer burnt
            uint256 burnAmount = amount.mul(5).div(100);
            // 95% of transfer sent to recipient
            uint256 sendAmount = amount.sub(burnAmount);
            require(amount == sendAmount + burnAmount, "COLOS::transfer: Burn value invalid");

            super._burn(sender, burnAmount);
            super._transfer(sender, recipient, sendAmount);
            amount = sendAmount;
        }
    }

}