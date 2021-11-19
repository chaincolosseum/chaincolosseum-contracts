pragma solidity ^0.6.2;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../MasterColosseum.sol";
import "./interfaces/IStakingBenefits.sol";
import "./FailsafeUpgradeable.sol";

contract StakingBenefitsUpgradeable is
    IStakingBenefits,
    Initializable,
    ReentrancyGuardUpgradeable,
    FailsafeUpgradeable,
    PausableUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    uint256 public override minimumStakeTime;
    uint256 public lastUpdateTime;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _stakeTimestamp;

    uint256 public override minimumStakeAmount;
    uint256 public override maxStakeAmount;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event MinimumStakeTimeUpdated(uint256 newMinimumStakeTime);
    event MinimumStakeAmountUpdated(uint256 newMinimumStakeAmount);
    event MaxStakeAmountUpdated(uint256 newMaxStakeAmount);
    event Recovered(address token, uint256 amount);

    function initialize(
        address _stakingToken,
        uint256 _minimumStakeTime,
        uint256 _minimumStakeAmount,
        uint256 _maxStakeAmount
    ) public virtual initializer {
        __Context_init();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __Failsafe_init_unchained();
        __ReentrancyGuard_init_unchained();

        stakingToken = IERC20(_stakingToken);
        minimumStakeTime = _minimumStakeTime;
        minimumStakeAmount = _minimumStakeAmount;
        maxStakeAmount = _maxStakeAmount;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function getStakeUnlockTimeLeft() external override view returns (uint256) {
        (bool success, uint256 diff) = _stakeTimestamp[msg.sender].add(minimumStakeTime).trySub(block.timestamp);
        if(success) {
            return diff;
        } else {
            return 0;
        }
    }

    function stake(uint256 amount) external override normalMode nonReentrant whenNotPaused {
        _stake(msg.sender, amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function _stake(address staker, uint256 amount) internal {
        require(amount >= minimumStakeAmount, "under min stake amount");
        require(_balances[staker].add(amount) <= maxStakeAmount, "max stake amount over");
        _totalSupply = _totalSupply.add(amount);
        _balances[staker] = _balances[staker].add(amount);
        if (_stakeTimestamp[staker] == 0) {
            _stakeTimestamp[staker] = block.timestamp;
        }
        emit Staked(staker, amount);
    }

    function withdraw(uint256 amount) public override normalMode nonReentrant {
        require(
            minimumStakeTime == 0 ||
                block.timestamp.sub(_stakeTimestamp[msg.sender]) >= minimumStakeTime,
                "You can't withdraw until after the minimum staking time.");
        _unstake(msg.sender, amount);
        stakingToken.safeTransfer(msg.sender, amount);
    }

    function _unstake(address staker, uint256 amount) internal {
        require(amount > 0, "withdraw amount is zero");
        _totalSupply = _totalSupply.sub(amount);
        _balances[staker] = _balances[staker].sub(amount);
        if (_balances[staker] == 0) {
            _stakeTimestamp[staker] = 0;
        } else {
            _stakeTimestamp[staker] = block.timestamp;
        }
        emit Withdrawn(staker, amount);
    }

    function exit() external override normalMode {
        withdraw(_balances[msg.sender]);
    }

    function recoverOwnStake() external failsafeMode {
        uint256 amount = _balances[msg.sender];
        if (amount > 0) {
            _totalSupply = _totalSupply.sub(amount);
            _balances[msg.sender] = _balances[msg.sender].sub(amount);
            stakingToken.safeTransfer(msg.sender, amount);
        }
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "Can't withdraw");
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setMinimumStakeTime(uint256 _minimumStakeTime) external normalMode onlyOwner {
        minimumStakeTime = _minimumStakeTime;
        emit MinimumStakeTimeUpdated(_minimumStakeTime);
    }

    function setMinimumStakeAmount(uint256 _minimumStakeAmount) external normalMode onlyOwner {
        minimumStakeAmount = _minimumStakeAmount;
        emit MinimumStakeAmountUpdated(_minimumStakeAmount);
    }

    function setMaxStakeAmount(uint256 _maxStakeAmount) external normalMode onlyOwner {
        maxStakeAmount = _maxStakeAmount;
        emit MaxStakeAmountUpdated(_maxStakeAmount);
    }

    function enableFailsafeMode() public override normalMode onlyOwner {
        minimumStakeAmount = 0;
        minimumStakeTime = 0;
        super.enableFailsafeMode();
    }

    function contractTokenTransfer() external onlyOwner {
        uint256 amount = stakingToken.balanceOf(address(this)).sub(_totalSupply);
        if (amount > 0) {
            stakingToken.safeTransfer(owner(), amount);
        }
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }


}
