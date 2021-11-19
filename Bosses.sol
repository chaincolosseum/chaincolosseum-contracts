// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "./util.sol";

contract Bosses is Initializable, ERC721Upgradeable, AccessControlUpgradeable {
    using SafeMath for uint16;
    using SafeMath for uint8;
    using ABDKMath64x64 for int128;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");
    uint16 public maxLoseCount;

    function initialize () public initializer {
        __ERC721_init("ChainColosseum Boss", "CCB");
        __AccessControl_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        maxLoseCount = 3;
    }

    struct Boss {
        string name;
        string imageUrl;
        uint maxHP;
        uint HP;
        uint ATK;
        uint DEF;
        uint SPD;
        uint LUK;
        uint256 lastFightTimestamp;
        uint16 winCount;
        uint16 loseCount;
        uint256 totalGain;
        bool inFight;
        bool ownedByAdmin;
    }

    Boss[] private tokens;
    uint256 private lastMintedBlock;
    uint256 private firstMintedOfLastBlock;

    event NewBoss(uint256 indexed boss, address indexed minter);

    modifier restricted() {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
        _;
    }

    modifier noFreshLookup(uint256 id) {
        _noFreshLookup(id);
        _;
    }

    function _noFreshLookup(uint256 id) internal view {
        require(id < firstMintedOfLastBlock || lastMintedBlock < block.number, "Too fresh for lookup");
    }

    function get(uint256 id) public view returns (string memory, string memory, bool, uint[] memory) {
        Boss memory b = tokens[id];
        uint[] memory params = new uint[](11);
        params[0] = b.maxHP;
        params[1] = b.HP;
        params[2] = b.ATK;
        params[3] = b.DEF;
        params[4] = b.SPD;
        params[5] = b.LUK;
        params[6] = getPower(id);
        params[7] = getLevel(id);
        params[8] = b.winCount;
        params[9] = b.loseCount;
        params[10] = b.totalGain;
        return (b.name, b.imageUrl, b.inFight, params);
    }

    function mint(address minter, string memory name, string memory imageUrl, uint HP, uint ATK, uint DEF, uint SPD, uint LUK, bool ownedByAdmin) public restricted returns (uint256) {
        uint256 tokenID = tokens.length;

        if(block.number != lastMintedBlock)
            firstMintedOfLastBlock = tokenID;
        lastMintedBlock = block.number;

        tokens.push(Boss(name, imageUrl, HP, HP, ATK, DEF, SPD, LUK, 0, 0,0, 0, false, ownedByAdmin));
        _mint(minter, tokenID);
        emit NewBoss(tokenID, minter);
        return tokenID;
    }

    function getName(uint256 id) public view returns (string memory) {
        return tokens[id].name;
    }

    function getImageUrl(uint256 id) public view returns (string memory) {
        return tokens[id].imageUrl;
    }

    function getMaxHP(uint256 id) public view returns (uint) {
        return tokens[id].maxHP;
    }

    function getHP(uint256 id) public view returns (uint) {
        return tokens[id].HP;
    }

    function getATK(uint256 id) public view returns (uint) {
        return tokens[id].ATK;
    }

    function getDEF(uint256 id) public view returns (uint) {
        return tokens[id].DEF;
    }

    function getSPD(uint256 id) public view returns (uint) {
        return tokens[id].SPD;
    }

    function getLUK(uint256 id) public view returns (uint) {
        return tokens[id].LUK;
    }

    function getPower(uint256 id) public view returns (uint) {
        return (tokens[id].maxHP + tokens[id].ATK + tokens[id].DEF + tokens[id].SPD + tokens[id].LUK);
    }

    function getLevel(uint256 id) public view returns (uint) {
        return getPower(id).div(6000);
    }

    function getLastFightTimestamp(uint256 id) public view returns (uint256) {
        return tokens[id].lastFightTimestamp;
    }

    function getTotalGain(uint256 id) public view returns (uint) {
        return tokens[id].totalGain;
    }

    function getOwnedByAdmin(uint256 id) public view returns (bool) {
        return tokens[id].ownedByAdmin;
    }

    function setName(uint256 id, string memory _name) public restricted {
        tokens[id].name = _name;
    }

    function setImageUrl(uint256 id, string memory _imageUrl) public restricted {
        tokens[id].imageUrl = _imageUrl;
    }

    function setMaxHP(uint256 id, uint _maxHP) public restricted {
        tokens[id].maxHP = _maxHP;
    }

    function setHP(uint256 id, uint _HP) public restricted {
        tokens[id].HP = _HP;
    }

    function setATK(uint256 id, uint _ATK) public restricted {
        tokens[id].ATK = _ATK;
    }

    function setDEF(uint256 id, uint _DEF) public restricted {
        tokens[id].DEF = _DEF;
    }

    function setSPD(uint256 id, uint _SPD) public restricted {
        tokens[id].SPD = _SPD;
    }

    function setLUK(uint256 id, uint _LUK) public restricted {
        tokens[id].LUK = _LUK;
    }

    function setLastFightTimestamp(uint256 id, uint256 timestamp) public restricted {
        tokens[id].lastFightTimestamp = timestamp;
    }

    function setInFight(uint256 id, bool _inFight) public restricted {
        tokens[id].inFight = _inFight;
    }

    function setMaxLoseCount(uint8 _maxLoseCount) public restricted {
        maxLoseCount = _maxLoseCount;
    }

    function addTotalGain(uint256 id, uint256 gain) public restricted {
        tokens[id].totalGain += gain;
    }

    function getCount(uint256 id) public view returns (uint16, uint16) {
        return (tokens[id].winCount, tokens[id].loseCount);
    }

    function incrementWinCount(uint256 id) public restricted {
        tokens[id].winCount++;
    }

    function incrementLoseCount(uint256 id) public restricted {
        tokens[id].loseCount++;
    }

    function getLength() public view returns (uint) {
        return tokens.length;
    }

    function getBossesByLevel(uint minLevel, uint maxLevel) public view returns (uint256[] memory) {
        uint256 num = getNumberOfBossesByLevel(minLevel, maxLevel);
        if(num == 0) {
            uint256[] memory bossIds = new uint256[](1);
            bossIds[0] = 0;
            return bossIds;
        }

        uint256[] memory bossIds = new uint256[](num);

        uint8 idIterator = 0;
        for(uint i = 0; i < tokens.length; i++) {
            if(getLevel(i) >= minLevel && getLevel(i) <= maxLevel && tokens[i].loseCount < maxLoseCount) {
                bossIds[idIterator] = i;
                idIterator++;
            }
        }
        return bossIds;
    }

    function getNumberOfBossesByLevel(uint minLevel, uint maxLevel) internal view returns (uint256) {
        uint count = 0;
        for(uint i = 0; i < tokens.length; i++) {
            if(getLevel(i) >= minLevel && getLevel(i) <= maxLevel && tokens[i].loseCount < maxLoseCount) {
                count++;
            }
        }
        return count;
    }

}
