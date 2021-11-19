// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "./SkillToken.sol";
import "./Items.sol";
import "./util.sol";
import "./LPStakingBenefitsUpgradeable.sol";

contract Characters is Initializable, ERC721Upgradeable, AccessControlUpgradeable {
    using SafeMathUpgradeable for uint256;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    uint256 public FIGHT_COOLDOWN_SECONDS; // 3600 = 1 hour (1 * 60 * 60);
    uint256 public MAX_SHORTENING_SECONDS; // 1800 = 1 hour - 30 min;

    uint256 public FIGHT_BOSS_COOLDOWN_SECONDS; // 86400 = 24 hour (24 * 60 * 60);
    uint256 public MAX_BOSS_SHORTENING_SECONDS; // 43200 = 24 hour - 12 hour;

    SkillToken public skill;
    Items public items;
    // shortening FIGHT_COOLDOWN_SECONDS by staking amount
    StakingBenefitsUpgradeable public staking;

    function initialize (
        SkillToken _skill,
        Items _items
    ) public initializer {
        __ERC721_init("ChainColosseum Character", "CCC");
        __AccessControl_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        skill = _skill;
        items = _items;
    }

    function setup_cooldown(
        uint256 _FIGHT_COOLDOWN_SECONDS,
        uint256 _MAX_SHORTENING_SECONDS,
        uint256 _FIGHT_BOSS_COOLDOWN_SECONDS,
        uint256 _MAX_BOSS_SHORTENING_SECONDS
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        FIGHT_COOLDOWN_SECONDS = _FIGHT_COOLDOWN_SECONDS;
        MAX_SHORTENING_SECONDS = _MAX_SHORTENING_SECONDS;
        FIGHT_BOSS_COOLDOWN_SECONDS = _FIGHT_BOSS_COOLDOWN_SECONDS;
        MAX_BOSS_SHORTENING_SECONDS = _MAX_BOSS_SHORTENING_SECONDS;
    }

    function migrate_staking(LPStakingBenefitsUpgradeable _staking) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        staking = _staking;
    }

    struct Character {
        uint8 job;
        uint HP;
        uint ATK;
        uint DEF;
        uint SPD;
        uint LUK;
        uint8 allocHP;
        uint8 allocATK;
        uint8 allocDEF;
        uint8 allocSPD;
        uint8 allocLUK;
        uint256 lastFightTimestamp;
        uint256 lastFightBossTimestamp;
        uint8 fightRound;
        uint16 winCountFirst;
        uint16 winCountSecond;
        uint16 winCountThird;
        uint16 winCountBoss;
    }

    Character[] private tokens;

    uint256 private lastMintedBlock;
    uint256 private firstMintedOfLastBlock;

    event NewCharacter(uint256 indexed character, address indexed minter);
    event BoostCharacter(uint256 indexed character, address indexed owner);
    event AdvancedJob(uint256 indexed character, address indexed owner);

    modifier restricted() {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
        _;
    }

    function get(uint256 id) public view returns (uint8, uint[] memory) {
        Character memory c = tokens[id];
        uint[] memory params = getParams(id);
        return (c.job, params);
    }

    function getSkillParam(uint256 _id) public view returns (uint, uint, uint, uint, uint, uint, uint) {
        uint256 id = _id;
        Character memory c = tokens[id];
        return (calcSkillParameter(c.HP, c.allocHP, ownerOf(id)),
                calcSkillParameter(c.ATK, c.allocATK, ownerOf(id)),
                calcSkillParameter(c.DEF, c.allocDEF, ownerOf(id)),
                calcSkillParameter(c.SPD, c.allocSPD, ownerOf(id)),
                calcSkillParameter(c.LUK, c.allocLUK, ownerOf(id)),
                getSkillPower(id, ownerOf(id)),
                getSkillLevel(id, ownerOf(id)));
    }

    function mint(address minter, uint256 seed) public restricted {
        uint8 job = uint8(seed % 3);

        (uint HP, uint ATK, uint DEF, uint SPD, uint LUK) = _callLuidaBar(job, seed);
        (uint8 allocHP, uint8 allocATK, uint8 allocDEF, uint8 allocSPD, uint8 allocLUK) = _getJobAllocation(job);
        uint256 tokenID = tokens.length;

        if(block.number != lastMintedBlock)
            firstMintedOfLastBlock = tokenID;
        lastMintedBlock = block.number;

        tokens.push(Character(job, HP, ATK, DEF, SPD, LUK, allocHP, allocATK, allocDEF, allocSPD, allocLUK, 0,0,0, 0,0,0,0));
        _mint(minter, tokenID);
        emit NewCharacter(tokenID, minter);
    }

    function _callLuidaBar(uint8 _job, uint256 seed) internal pure returns (uint, uint, uint, uint, uint) {
        uint HP = 100;
        uint ATK = 100;
        uint DEF = 100;
        uint SPD = 100;
        uint LUK = 100;

        uint256 nonce = 0;

        if (_job == 0) { // Warrior
            HP += uint(RandomUtil.randomSeededMinMax(30,50,(seed + nonce++)));
            ATK += uint(RandomUtil.randomSeededMinMax(30,50,(seed + nonce++)));
            DEF += uint(RandomUtil.randomSeededMinMax(20,40,(seed + nonce++)));
            SPD += uint(RandomUtil.randomSeededMinMax(3,10,(seed + nonce++)));
            LUK += uint(RandomUtil.randomSeededMinMax(3,10,(seed + nonce++)));
        } else if (_job == 1) { // Thief
            HP += uint(RandomUtil.randomSeededMinMax(25,50,(seed + nonce++)));
            ATK += uint(RandomUtil.randomSeededMinMax(25,45,(seed + nonce++)));
            DEF += uint(RandomUtil.randomSeededMinMax(20,40,(seed + nonce++)));
            SPD += uint(RandomUtil.randomSeededMinMax(30,45,(seed + nonce++)));
            LUK += uint(RandomUtil.randomSeededMinMax(5,10,(seed + nonce++)));
        } else if (_job == 2) { // Investor
            HP += uint(RandomUtil.randomSeededMinMax(20,35,(seed + nonce++)));
            ATK += uint(RandomUtil.randomSeededMinMax(15,25,(seed + nonce++)));
            DEF += uint(RandomUtil.randomSeededMinMax(15,20,(seed + nonce++)));
            SPD += uint(RandomUtil.randomSeededMinMax(15,25,(seed + nonce++)));
            LUK += uint(RandomUtil.randomSeededMinMax(40,60,(seed + nonce++)));
        }
        return (HP, ATK, DEF, SPD, LUK);
    }

    function _getJobAllocation(uint8 _job) internal pure returns (uint8, uint8, uint8, uint8, uint8) {
        // Basic Job
        if (_job == 0) {
            return (30, 30, 26, 6, 8); // 100
        } else if (_job == 1) {
            return (26, 24, 20, 24, 16); // 110
        } else if (_job == 2) {
            return (24, 20, 18, 20, 30); // 112
        }
        // Advance Job
        else if (_job == 10) {
            return (45, 45, 40, 10, 12);
        } else if (_job == 11) {
            return (40, 36, 30, 36, 24);
        } else if (_job == 12) {
            return (36, 30, 28, 30, 45);
        }
    }

    function getCanBeEquiped(uint8 _job) public pure returns (uint8[] memory) {
        uint8[] memory kinds = new uint8[](10);
        if (_job == 0 || _job == 10) {
            kinds[0] = 0;
            kinds[1] = 1;
            kinds[2] = 5;
            kinds[3] = 10;
            kinds[4] = 11;
            kinds[5] = 12;
            kinds[6] = 13;
        } else if (_job == 1 || _job == 11) {
            kinds[0] = 0;
            kinds[1] = 3;
            kinds[2] = 4;
            kinds[3] = 11;
            kinds[4] = 12;
            kinds[5] = 13;
            kinds[6] = 21;
        } else if (_job == 2 || _job == 12) {
            kinds[0] = 0;
            kinds[1] = 2;
            kinds[2] = 4;
            kinds[3] = 11;
            kinds[4] = 12;
            kinds[5] = 13;
            kinds[6] = 20;
            kinds[7] = 21;
        }
        return kinds;
    }

    function getJob(uint256 id) public view returns (uint8) {
        return tokens[id].job;
    }

    function getParams(uint256 id) public view returns (uint[] memory) {
        uint[] memory params = new uint[](7);
        params[0] = tokens[id].HP;
        params[1] = tokens[id].ATK;
        params[2] = tokens[id].DEF;
        params[3] = tokens[id].SPD;
        params[4] = tokens[id].LUK;
        params[5] = getPower(id);
        params[6] = getLevel(id);
        return params;
    }

    function getPower(uint256 id) public view returns (uint) {
        return (tokens[id].HP + tokens[id].ATK + tokens[id].DEF + tokens[id].SPD + tokens[id].LUK);
    }

    function getLevel(uint256 id) public view returns (uint) {
        return getPower(id).div(100);
    }

    function getSkillAllocation(uint256 id) public view returns (uint8, uint8, uint8, uint8, uint8) {
        Character memory c = tokens[id];
        return (c.allocHP, c.allocATK, c.allocDEF, c.allocSPD, c.allocLUK);
    }

    function calcSkillParameter(uint param, uint8 allocParam, address user) internal view returns (uint) {
        uint256 skillAmount = getTotalSkillOwnedBy(user).div(1 ether);
        // 1/10
        return param.add(skillAmount.mul(allocParam).div(100).div(10));
    }

    function getSkillPower(uint256 id, address user) public view returns (uint) {
        Character memory c = tokens[id];
        return calcSkillParameter(c.HP, c.allocHP, user) +
            calcSkillParameter(c.ATK, c.allocATK, user) +
            calcSkillParameter(c.DEF, c.allocDEF, user) +
            calcSkillParameter(c.SPD, c.allocSPD, user) +
            calcSkillParameter(c.LUK, c.allocLUK, user);
    }

    function getSkillLevel(uint256 id, address user) public view returns (uint) {
        return getSkillPower(id, user).div(100);
    }

    function calcFixParameter(uint param, uint8 allocParam, address user, int128 itemVal) internal view returns (uint) {
        return calcSkillParameter(param, allocParam, user).add(uint256(itemVal));
    }

    function getFixParams(uint256 id, uint256[] memory itemIds, address user) public view returns (uint[] memory) {
        int128[] memory itemVals = new int128[](6);
        for (uint i = 0; i < itemIds.length; i++ ){
            itemVals[0] += items.getHP(itemIds[i]);
            itemVals[1] += items.getATK(itemIds[i]);
            itemVals[2] += items.getDEF(itemIds[i]);
            itemVals[3] += items.getSPD(itemIds[i]);
            itemVals[4] += items.getLUK(itemIds[i]);
            itemVals[5] += items.getPower(itemIds[i]);
        }

        uint[] memory params = new uint[](6);
        params[0] = calcFixParameter(tokens[id].HP, tokens[id].allocHP, user, itemVals[0]);
        params[1] = calcFixParameter(tokens[id].ATK, tokens[id].allocATK, user, itemVals[1]);
        params[2] = calcFixParameter(tokens[id].DEF, tokens[id].allocDEF, user, itemVals[2]);
        params[3] = calcFixParameter(tokens[id].SPD, tokens[id].allocSPD, user, itemVals[3]);
        params[4] = calcFixParameter(tokens[id].LUK, tokens[id].allocLUK, user, itemVals[4]);
        params[5] = calcFixParameter(getPower(id), 100, user, itemVals[5]);
        return params;
    }

    function getFixHP(uint256 id, uint256[] memory itemIds, address user) public view returns (uint) {
        int128 itemVal = 0;
        for (uint i = 0; i < itemIds.length; i++ ){
            itemVal += items.getHP(itemIds[i]);
        }
        return calcFixParameter(tokens[id].HP, tokens[id].allocHP, user, itemVal);
    }

    function getFixPower(uint256 id, uint256[] memory itemIds, address user) public view returns (uint) {
        int128 itemVal = 0;
        for (uint i = 0; i < itemIds.length; i++ ){
            itemVal += items.getPower(itemIds[i]);
        }
        return calcFixParameter(getPower(id), 100, user, itemVal);
    }

    function getTotalSkillOwnedBy(address wallet) public view returns (uint256) {
        return skill.balanceOf(wallet);
    }

    function getLastFightTimestamp(uint256 id) public view returns (uint256) {
        return tokens[id].lastFightTimestamp;
    }

    function getLastFightBossTimestamp(uint256 id) public view returns (uint256) {
        return tokens[id].lastFightBossTimestamp;
    }

    function setLastFightTimestamp(uint256 id, uint256 timestamp) public restricted {
        tokens[id].lastFightTimestamp = timestamp;
    }

    function setLastFightBossTimestamp(uint256 id, uint256 timestamp) public restricted {
        tokens[id].lastFightBossTimestamp = timestamp;
    }

    function getFightRound(uint256 id) public view returns (uint64) {
        return tokens[id].fightRound;
    }

    function setFightRound(uint256 id, uint8 fightRound) public restricted {
        tokens[id].fightRound = fightRound;
    }

    function incrementWinCountFirst(uint256 id) public restricted {
        tokens[id].winCountFirst++;
    }

    function incrementWinCountSecond(uint256 id) public restricted {
        tokens[id].winCountSecond++;
    }

    function incrementWinCountThird(uint256 id) public restricted {
        tokens[id].winCountThird++;
    }

    function incrementWinCountBoss(uint256 id) public restricted {
        tokens[id].winCountBoss++;
    }

    function canFight(uint256 id) public view returns (bool) {
        return canFightFromTimestamp(tokens[id].lastFightTimestamp);
    }

    function canFightBoss(uint256 id) public view returns (bool) {
        return canFightBossFromTimestamp(tokens[id].lastFightBossTimestamp);
    }

    function canFightFromTimestamp(uint256 timestamp) public view returns (bool) {
        if(timestamp  > now)
            return false;

        uint256 fightCooldownSeconds = getFightCooldownSeconds();

        if((now - timestamp) >= fightCooldownSeconds) {
            return true;
        } else {
            return false;
        }
    }

    function canFightBossFromTimestamp(uint256 timestamp) public view returns (bool) {
        if(timestamp  > now)
            return false;

        uint256 fightBossCooldownSeconds = getFightBossCooldownSeconds();

        if((now - timestamp) >= fightBossCooldownSeconds) {
            return true;
        } else {
            return false;
        }
    }

    function getFightCooldownSeconds() public view returns (uint256) {
        uint256 shorteningTime = (staking.balanceOf(msg.sender).mul(MAX_SHORTENING_SECONDS)).div(staking.maxStakeAmount());
        uint256 fightCooldownSeconds = 0;
        if (FIGHT_COOLDOWN_SECONDS >= shorteningTime) {
            fightCooldownSeconds = FIGHT_COOLDOWN_SECONDS.sub(shorteningTime);
        }
        return fightCooldownSeconds;
    }

    function getFightBossCooldownSeconds() public view returns (uint256) {
        uint256 shorteningTime = (staking.balanceOf(msg.sender).mul(MAX_BOSS_SHORTENING_SECONDS)).div(staking.maxStakeAmount());
        uint256 fightBossCooldownSeconds = 0;
        if (FIGHT_BOSS_COOLDOWN_SECONDS >= shorteningTime) {
            fightBossCooldownSeconds = FIGHT_BOSS_COOLDOWN_SECONDS.sub(shorteningTime);
        }
        return fightBossCooldownSeconds;
    }

    function getTimeToCanFight(uint256 id) public view returns (uint256) {
        uint256 fightCooldownSeconds = getFightCooldownSeconds();
        uint256 waitTime = now - tokens[id].lastFightTimestamp;
        if (waitTime >= fightCooldownSeconds) {
            return 0;
        } else {
            return fightCooldownSeconds - waitTime;
        }
    }

    function getTimeToCanFightBoss(uint256 id) public view returns (uint256) {
        uint256 fightBossCooldownSeconds = getFightBossCooldownSeconds();
        uint256 waitTime = now - tokens[id].lastFightBossTimestamp;
        if (waitTime >= fightBossCooldownSeconds) {
            return 0;
        } else {
            return fightBossCooldownSeconds - waitTime;
        }
    }

    function boost(uint256 id, address owner, uint256 useSkillAmount) public restricted {
        uint256 skillAmount = getTotalSkillOwnedBy(owner).div(1 ether);
        require(skillAmount >= useSkillAmount, "insufficient skill in wallet");

        tokens[id].HP = tokens[id].HP.add(useSkillAmount.mul(tokens[id].allocHP).div(100));
        tokens[id].ATK = tokens[id].ATK.add(useSkillAmount.mul(tokens[id].allocATK).div(100));
        tokens[id].DEF = tokens[id].DEF.add(useSkillAmount.mul(tokens[id].allocDEF).div(100));
        tokens[id].SPD = tokens[id].SPD.add(useSkillAmount.mul(tokens[id].allocSPD).div(100));
        tokens[id].LUK = tokens[id].LUK.add(useSkillAmount.mul(tokens[id].allocLUK).div(100));

        emit BoostCharacter(id, owner);
    }

    function advancedJob(uint256 id, address owner) public restricted {
        require(getPower(id) >= 1000, "insufficient Power");
        require(tokens[id].job == 0 || tokens[id].job == 1 || tokens[id].job == 2, "not Basic Job");
        tokens[id].job = tokens[id].job + 10;
        (uint8 allocHP, uint8 allocATK, uint8 allocDEF, uint8 allocSPD, uint8 allocLUK) = _getJobAllocation(tokens[id].job);
        tokens[id].allocHP = allocHP;
        tokens[id].allocATK = allocATK;
        tokens[id].allocDEF = allocDEF;
        tokens[id].allocSPD = allocSPD;
        tokens[id].allocLUK = allocLUK;

        emit AdvancedJob(id, owner);
    }
}
