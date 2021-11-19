pragma solidity ^0.6.5;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Tickets.sol";
import "./Bosses.sol";

contract BossMintTickets is Tickets {
    using SafeMath for uint;

    Bosses bosses;

    event BossMinted(address indexed owner, uint256 indexed boss);

    function initialize(Bosses _bosses) public initializer {
        __AccessControl_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _enabled = true;
        bosses = _bosses;
    }

    function mintBoss(string memory name, string memory imageUrl, uint HP, uint ATK, uint DEF, uint SPD, uint LUK) public {
        uint Power = HP + ATK + DEF + SPD + LUK;
        uint level = Power.div(6000);
        require(ATK <= level.mul(45).add(75), "ATK is too high");
        require(DEF <= level.mul(45).add(75), "DEF is too high");
        require(SPD <= level.mul(20).add(120), "SPD is too high");
        require(LUK <= level.mul(20).add(120), "LUK is too high");
        consumeTicket(Power);
        uint256 bossId = bosses.mint(msg.sender, name, imageUrl, HP, ATK, DEF, SPD, LUK, false);
        emit BossMinted(msg.sender, bossId);
    }

}