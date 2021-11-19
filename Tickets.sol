pragma solidity ^0.6.5;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";


contract Tickets is Initializable, AccessControlUpgradeable {

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    mapping(address => uint) public owned;
    bool internal _enabled;

    event TicketGiven(address indexed owner, uint amount);

    function initialize() public initializer {
        __AccessControl_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _enabled = true;
    }

    modifier isAdmin() {
         require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    modifier ticketNotDisabled() {
         require(_enabled, "Ticket disabled");
        _;
    }

    modifier restricted() {
        _restricted();
        _;
    }

    function _restricted() internal view {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
    }

    modifier haveTicket(uint amount) {
        require(owned[msg.sender] >= amount, "No ticket");
        _;
    }

    function giveTicket(address buyer, uint amount) public restricted {
        owned[buyer] += amount;
        emit TicketGiven(buyer, amount);
    }

    function consumeTicket(uint amount) internal haveTicket(amount) ticketNotDisabled {
        owned[msg.sender] -= amount;
    }

    function getTicketCount() public view returns (uint) {
        return owned[msg.sender];
    }

    function toggleTicketCanUse(bool canUse) external isAdmin {
        _enabled = canUse;
    }

    function giveTicketByAdmin(address receiver, uint amount) external isAdmin {
        owned[receiver] += amount;
    }

    function takeTicketByAdmin(address target, uint amount) external isAdmin {
        require(owned[target] >= amount, 'Not enough ticket');
        owned[target] -= amount;
    }

    function ticketEnabled() public view returns (bool){
        return _enabled;
    }
}