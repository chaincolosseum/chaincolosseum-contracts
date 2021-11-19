// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../SkillToken.sol";
import "../Items.sol";

contract Presale is Initializable, AccessControlUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    SkillToken public token;
    // IERC20 public useToken;  // useToken is BNB

    Items public items;

    mapping(address => uint256) balances; // buyer address : token wei
    mapping(address => uint256) refBalances; // referral address : token wei
    mapping(address => uint256) ticketBalances; // buyer address : ticket amount

    struct Bought {
        address buyer;
        uint256 amount;
    }
    // mapping(address => mapping(address => Bought)) boughtByRef; // referral address : bought by referral
    mapping(address => Bought[]) boughtByRef; // referral address : bought by referral

    uint256 public totalPurchasedAmount; // in wei
    uint256 public totalReferralAmount; // in wei
    uint256 public totalTicketAmount;
    uint256 public rate;
    uint256 public refRate;
    uint256 public ticketRate;

    // timestamp when Claim release is enabled and Buy ended
    uint256 public releaseTime;

    // Limit parameter
    uint256 public hardCap;
    uint256 public limitPerAccount;
    uint256 public tokensPerMaxBuy;

    event TokenPurchase(address indexed purchaser, uint256 useAmount, uint256 buyAmount);
    event ClaimTokens(address indexed purchaser, uint256 claimAmount);
    event ClaimRefTokens(address indexed purchaser, uint256 claimAmount);
    event ClaimTickets(address indexed purchaser, uint256 claimAmount);

    function initialize(
        SkillToken _token,
        // IERC20 _useToken,
        Items _items,
        uint256 _rate,
        uint256 _refRate,
        uint256 _ticketRate,
        uint256 _releaseTime
    ) public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GAME_ADMIN, msg.sender);

        token = _token;
        // useToken = _useToken;
        items = _items;
        rate = _rate;
        refRate = _refRate;
        ticketRate = _ticketRate;
        releaseTime = _releaseTime;

        hardCap = uint256(990000).mul(10 ** 18); // 990000SKILL
        limitPerAccount = uint256(3).mul(rate).mul(10 ** 18); // 3BNB * rate SKILL
        tokensPerMaxBuy = uint256(3).mul(10 ** 18); // 3BNB
    }

    modifier onlyNonContract() {
        _onlyNonContract();
        _;
    }

    function _onlyNonContract() internal view {
        require(tx.origin == msg.sender, "Only Non Contract.");
    }

    modifier restricted() {
        _restricted();
        _;
    }

    function _restricted() internal view {
        require(hasRole(GAME_ADMIN, msg.sender), "Missing GAME_ADMIN role");
    }

    modifier requestBuy(uint256 useAmount) {
        _requestBuy(useAmount);
        _;
    }

    function _requestBuy(uint256 useAmount) internal view {
        // require(useToken.balanceOf(msg.sender) >= useAmount, "insufficient funds.");
        require(msg.sender.balance >= useAmount, "insufficient funds.");
    }

    function withdrawAll() public restricted {
        msg.sender.transfer(address(this).balance);
        safeTokenTransfer(msg.sender, token.balanceOf(address(this)));
    }

    function withdraw(uint256 amount) public restricted {
        msg.sender.transfer(amount);
    }

    function withdrawToken(uint256 amount) public restricted {
        safeTokenTransfer(msg.sender, amount);
    }

    function buyTokens(address referAddr) public payable onlyNonContract {
        require(block.timestamp < releaseTime, "current time is after release time");
        uint256 useAmount = msg.value;
        require(useAmount <= tokensPerMaxBuy, "over tokens per max buy.");
        // _requestBuy(useAmount);
        // payContract(useAmount);
        uint256 buyAmount = useAmount.mul(rate);
        require(balances[msg.sender].add(buyAmount) <= limitPerAccount, "over limit per account.");
        require(totalPurchasedAmount.add(buyAmount) <= hardCap, "over hard cap.");

        totalPurchasedAmount = totalPurchasedAmount.add(buyAmount);
        balances[msg.sender] = balances[msg.sender].add(buyAmount);
        TokenPurchase(msg.sender, useAmount, buyAmount);

        if(referAddr != address(0) && referAddr != msg.sender) {
            uint256 refAmount = useAmount.mul(refRate).div(1000);
            totalReferralAmount = totalReferralAmount.add(refAmount);
            refBalances[referAddr] = refBalances[referAddr].add(refAmount);
            Bought memory bought = Bought(msg.sender, useAmount);
            boughtByRef[referAddr].push(bought);
        }

        uint256 ticketAmount = useAmount.mul(ticketRate).div(10 ** 18);
        totalTicketAmount = totalTicketAmount.add(ticketAmount);
        ticketBalances[msg.sender] = ticketBalances[msg.sender].add(ticketAmount);
    }

    // function payContract(uint256 amount) public payable restricted {
    //     _payContract(msg.sender, amount);
    // }

    // function _payContract(address payable buyerAddress, uint256 amount) internal {
    //     useToken.transferFrom(buyerAddress, address(this), amount);
    // }

    function claimTokens() public onlyNonContract {
        require(block.timestamp >= releaseTime, "current time is before release time");
        uint256 tokens = balances[msg.sender];
        if(tokens > 0) {
            balances[msg.sender] = 0;
            token.mint(msg.sender, tokens);
            ClaimTokens(msg.sender, tokens);
        }
    }

    function claimRefTokens() public onlyNonContract {
        require(block.timestamp >= releaseTime, "current time is before release time");
        uint256 tokens = refBalances[msg.sender];
        if(tokens > 0) {
            refBalances[msg.sender] = 0;
            msg.sender.transfer(tokens);
            ClaimRefTokens(msg.sender, tokens);
        }
    }

    function claimTickets() public onlyNonContract {
        require(block.timestamp >= releaseTime, "current time is before release time");
        uint256 tickets = ticketBalances[msg.sender];
        if(tickets > 0) {
            ticketBalances[msg.sender] = 0;
            items.giveBossMintTicket(msg.sender, tickets);
            ClaimTickets(msg.sender, tickets);
        }
    }

    function safeTokenTransfer(address _to, uint256 _total) internal {
        // no Fee!
        uint256 _amount = _total;

        uint256 tokenBal = token.balanceOf(address(this));
        bool transferSuccess = false;

        if (tokenBal > 0) {
            if (_amount > tokenBal) {
                transferSuccess = token.transfer(_to, tokenBal);
            } else {
                transferSuccess = token.transfer(_to, _amount);
            }
        } else {
            transferSuccess = true;
        }

        require(transferSuccess, "safeTokenTransfer: Transfer failed");
    }

    function getOwnBalance() public view returns (uint256) {
        return balances[msg.sender];
    }

    function getOwnRefBalance() public view returns (uint256) {
        return refBalances[msg.sender];
    }

    function getOwnTicketBalance() public view returns (uint256) {
        return ticketBalances[msg.sender];
    }

    function getOwnBoughtByRef() public view returns (address[] memory, uint256[] memory) {
        Bought[] memory bought = boughtByRef[msg.sender];
        address[] memory addr = new address[](bought.length);
        uint256[] memory amount = new uint256[](bought.length);
        for(uint i = 0; i < bought.length; i++) {
            addr[i] = bought[i].buyer;
            amount[i] = bought[i].amount;
        }
        return (addr, amount);
    }

    function getBalance(address buyer) public view restricted returns (uint256) {
        return balances[buyer];
    }

    function getRefBalance(address refer) public view restricted returns (uint256) {
        return refBalances[refer];
    }

    function getBoughtByRef(address refer) public view restricted returns (address[] memory, uint256[] memory) {
        Bought[] memory bought = boughtByRef[refer];
        address[] memory addr = new address[](bought.length);
        uint256[] memory amount = new uint256[](bought.length);
        for(uint i = 0; i < bought.length; i++) {
            addr[i] = bought[i].buyer;
            amount[i] = bought[i].amount;
        }
        return (addr, amount);
    }

    function getTicketBalance(address buyer) public view restricted returns (uint256) {
        return ticketBalances[buyer];
    }

    function getReleased() public view returns (bool) {
        return block.timestamp >= releaseTime;
    }

    function setReleaseTime(uint256 _releaseTime) public restricted {
        releaseTime = _releaseTime;
    }

    function setRate(uint256 _rate) public restricted {
        rate = _rate;
    }

    function setRefRate(uint256 _refRate) public restricted {
        refRate = _refRate;
    }

    function setBuyerBalance(address buyer, uint256 balance) public restricted {
        balances[buyer] = balance;
    }

    function setRefBalance(address refer, uint256 balance) public restricted {
        refBalances[refer] = balance;
    }

    function setTicketBalance(address buyer, uint256 balance) public restricted {
        ticketBalances[buyer] = balance;
    }

    function setHardCap(uint256 amount) public restricted {
        hardCap = amount;
    }

    function setLimitPerAccount(uint256 amount) public restricted {
        limitPerAccount = amount;
    }

    function setTokensPerMaxBuy(uint256 amount) public restricted {
        tokensPerMaxBuy = amount;
    }
}