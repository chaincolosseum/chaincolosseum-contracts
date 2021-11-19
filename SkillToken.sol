// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./ColosToken.sol";

contract SkillToken is ERC20, ERC20Burnable, Ownable {
    using SafeMath for uint256;

    struct HolderInfo {
        uint256 avgTransactionBlock;
    }

    ColosToken public colos;
    address public game;
    address public sale;

    uint256 public SWAP_PENALTY_MAX_PERIOD ; // after 600h penalty of holding skill. Swap penalty is at the minimum
    uint256 public SWAP_PENALTY_MAX_PER_SKILL ; // 50% => 1 skill = 0.5 colos

    mapping(address => HolderInfo) public holdersInfo;

    constructor (uint256 swapPenaltyMaxPeriod, uint256 swapPenaltyMaxPerSkill) public ERC20("ChainColosseum Skill Token", "SKILL") {
        SWAP_PENALTY_MAX_PERIOD = swapPenaltyMaxPeriod;
        SWAP_PENALTY_MAX_PER_SKILL = swapPenaltyMaxPerSkill.mul(1e10);
        _mint(address(this), 1000000 * (10 ** uint256(decimals())));
        _approve(address(this), msg.sender, totalSupply());
    }

    modifier onlyOwnerOrGameOrColosOrSale() {
        require(isOwner() || isGame() || isColos() || isSale(), "caller is not the owner or game or colos or sale");
        _;
    }

    function isOwner() public view returns (bool) {
        return msg.sender == owner();
    }

    function isGame() internal view returns (bool) {
        return msg.sender == address(game);
    }

    function isColos() internal view returns (bool) {
        return msg.sender == address(colos);
    }

    function isSale() internal view returns (bool) {
        return msg.sender == address(sale);
    }

    function setupGame(address _game) external onlyOwner{
        game = _game;
    }

    function setupSale(address _sale) external onlyOwner{
        sale = _sale;
    }

    function setupColos(ColosToken _colos) external onlyOwner{
        colos = _colos;
    }

    function setSwapPenalty(uint256 maxPeriod, uint256 maxPerSkill) external onlyOwner {
        SWAP_PENALTY_MAX_PERIOD = maxPeriod;
        SWAP_PENALTY_MAX_PER_SKILL = maxPerSkill.mul(1e10);
    }

    /* Calculate the penality for swapping skill to colos for a user.
       The penality decrease over time (by holding duration).
       From SWAP_PENALTY_MAX_PER_SKILL % to 0% on SWAP_PENALTY_MAX_PERIOD
    */
    function getPenaltyPercent(address _holderAddress) public view returns (uint256){
        HolderInfo storage holderInfo = holdersInfo[_holderAddress];
        if(block.number >= holderInfo.avgTransactionBlock.add(SWAP_PENALTY_MAX_PERIOD)){
            return 0;
        }
        if(block.number == holderInfo.avgTransactionBlock){
            return SWAP_PENALTY_MAX_PER_SKILL;
        }
        uint256 avgHoldingDuration = block.number.sub(holderInfo.avgTransactionBlock);
        return SWAP_PENALTY_MAX_PER_SKILL.sub(
            SWAP_PENALTY_MAX_PER_SKILL.mul(avgHoldingDuration).div(SWAP_PENALTY_MAX_PERIOD)
        );
    }

    /* Allow use to exchange (swap) their skill to colos */
    function swapToColos(uint256 _amount) external {
        require(_amount > 0, "amount 0");
        address _from = msg.sender;
        uint256 colosAmount = _swapColosAmount( _from, _amount);
        holdersInfo[_from].avgTransactionBlock = _getAvgTransactionBlock(_from, holdersInfo[_from], _amount, true);
        super._burn(_from, _amount);
        colos.mint(_from, colosAmount);
    }

    /* @notice Preview swap return in colos with _skillAmount by _holderAddress
    *  this function is used by front-end to show how much colos will be retrieve if _holderAddress swap _skillAmount
    */
    function previewSwapColosExpectedAmount(address _holderAddress, uint256 _skillAmount) external view returns (uint256 expectedColos){
        return _swapColosAmount( _holderAddress, _skillAmount);
    }

    /* @notice Calculate the adjustment for a user if he want to swap _skillAmount to colos */
    function _swapColosAmount(address _holderAddress, uint256 _skillAmount) internal view returns (uint256 expectedColos){
        require(balanceOf(_holderAddress) >= _skillAmount, "Not enough SKILL");
        uint256 penalty = getPenaltyPercent(_holderAddress);
        if(penalty == 0){
            return _skillAmount;
        }

        return _skillAmount.sub(_skillAmount.mul(penalty).div(1e12));
    }

    /* @notice Calculate average deposit/withdraw block for _holderAddress */
    function _getAvgTransactionBlock(address _holderAddress, HolderInfo storage holderInfo, uint256 _skillAmount, bool _onWithdraw) internal view returns (uint256){
        if (balanceOf(_holderAddress) == 0) {
            return block.number;
        }
        uint256 transactionBlockWeight;
        if (_onWithdraw) {
            if (balanceOf(_holderAddress) == _skillAmount) {
                return 0;
            }
            else {
                return holderInfo.avgTransactionBlock;
            }
        }
        else {
            transactionBlockWeight = (balanceOf(_holderAddress).mul(holderInfo.avgTransactionBlock).add(block.number.mul(_skillAmount)));
        }
        return transactionBlockWeight.div(balanceOf(_holderAddress).add(_skillAmount));
    }


    /// @notice Creates `_amount` token to `_to`.
    function mint(address _to, uint256 _amount) external virtual onlyOwnerOrGameOrColosOrSale {
        HolderInfo storage holder = holdersInfo[_to];
        holder.avgTransactionBlock = _getAvgTransactionBlock(_to, holder, _amount, false);
        _mint(_to, _amount);
    }

    /// @dev overrides transfer function to meet tokenomics of SKILL
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        require(amount > 0, "amount 0");
        holdersInfo[sender].avgTransactionBlock = _getAvgTransactionBlock(sender, holdersInfo[sender], amount, true);
        if (recipient == 0x000000000000000000000000000000000000dEaD) {
            super._burn(sender, amount);
        } else {
            holdersInfo[recipient].avgTransactionBlock = _getAvgTransactionBlock(recipient, holdersInfo[recipient], amount, false);
            // 5% of every transfer burnt
            uint256 burnAmount = amount.mul(5).div(100);
            // 95% of transfer sent to recipient
            uint256 sendAmount = amount.sub(burnAmount);
            require(amount == sendAmount + burnAmount, "SKILL::transfer: Burn value invalid");

            super._burn(sender, burnAmount);
            super._transfer(sender, recipient, sendAmount);
            amount = sendAmount;
        }
    }
}