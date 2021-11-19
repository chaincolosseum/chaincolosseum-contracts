pragma solidity >=0.4.24;

interface IStakingBenefits {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function minimumStakeAmount() external view returns (uint256);
    function maxStakeAmount() external view returns (uint256);
    function minimumStakeTime() external view returns (uint256);
    function getStakeUnlockTimeLeft() external view returns (uint256);

    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function exit() external;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event MinimumStakeTimeUpdated(uint256 newMinimumStakeTime);
}
