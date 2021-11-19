pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "./MasterColosseum.sol";
import "./Characters.sol";
import "./Items.sol";
import "./Bosses.sol";
import "./ColosToken.sol";
import "./Fight.sol";
import "./util.sol";

contract Raid is Initializable, AccessControlUpgradeable {
    using SafeMath for uint;
    using SafeMath for uint8;
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;
    using SignedSafeMath for int256;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    MasterColosseum public game;
    Characters public characters;
    Items public items;
    Bosses public bosses;
    ColosToken public colos;
    Fight public fight;

    mapping(uint8 => uint256) public raidBossIds; // key: raidLevel(1-30), value: bossId

    int128 public fightBossRewardSkillBaseline;
    int128 public fightBossRewardColosBaseline;
    int128 public fightBossRewardGasOffset;

    mapping(address => uint256) lastBlockNumberCalled;

    struct Parameters {
        int256 HP;
        uint ATK;
        uint DEF;
        uint SPD;
        uint LUK;
        uint Power;
    }

    event FightOutcome(address indexed owner, bool win, uint256 indexed character, uint256 playerPower, uint256 targetPower, uint256 targetHP, uint256 skillGain, uint256 colosGain);
    event Attack(address indexed user, uint turn, int256 damage, uint state); // state: 0:miss, 1:normal, 2:critical
    event Damage(address indexed user, uint turn, int256 damage, uint state); // state: 0:miss, 1:normal, 2:critical

    function initialize(address gameContract, Bosses _bosses, Fight _fight) public initializer {

        __AccessControl_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GAME_ADMIN, msg.sender);

        game = MasterColosseum(gameContract);
        characters = Characters(game.characters());
        items = Items(game.items());
        colos = ColosToken(game.colos());
        bosses = _bosses;
        fight = _fight;

        fightBossRewardGasOffset = ABDKMath64x64.divu(46354, 100000); // 0.0539 x 4.3 x 2
        fightBossRewardSkillBaseline = ABDKMath64x64.divu(1000, 1000);
        fightBossRewardColosBaseline = ABDKMath64x64.divu(3000, 1000);
    }

    modifier restricted() {
        _restricted();
        _;
    }

    function _restricted() internal view {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
    }

    modifier fightModifierChecks(uint256 char, uint256[] memory itemIds, uint256 boss) {
        require(tx.origin == msg.sender, "Only EOA allowed (temporary)");
        require(lastBlockNumberCalled[msg.sender] < block.number, "Only callable once per block");
        lastBlockNumberCalled[msg.sender] = block.number;
        uint256 myBoss = getMyBoss(char, itemIds);
        require(boss == myBoss, "Not the correct raidBossId");
        require(characters.ownerOf(char) == msg.sender, "Not the character owner");
        require(characters.canFightBoss(char) == true, "this character can't fight in first round");
        for (uint i = 0; i < itemIds.length; i++) {
            require(items.ownerOf(itemIds[i]) == msg.sender, "Not the item owner");
        }
        for (uint i = 0; i < itemIds.length; i++) {
            uint8[] memory kinds = characters.getCanBeEquiped(characters.getJob(char));
            bool found = false;
            for (uint j = 0; j < kinds.length; j++) {
                if(kinds[j] == items.getKind(itemIds[i])){
                    found = true;
                    break;
                }
            }
            require(found, "This job cannot equip this item");
        }
        // Duplicate equipment check
        uint8[] memory kinds = new uint8[](itemIds.length);
        for (uint i = 0; i < itemIds.length; i++) {
            kinds[i] = 99;
        }
        bool found = false;
        for (uint i = 0; i < itemIds.length; i++) {
            for (uint j = 0; j < kinds.length; j++) {
                if(kinds[j] == items.getKind(itemIds[i])) {
                    found = true;
                    break;
                }
            }
            kinds[i] = items.getKind(itemIds[i]);
        }
        require(!found, "Duplicate equipment");

        // Duplicate weapon equipment check
        found = false;
        for (uint i = 0; i < itemIds.length; i++) {
            uint8 kind = items.getKind(itemIds[i]);
            if (kind < 10) {
                if (found == false) {
                    found == true;
                } else {
                    require(false, "Duplicate weapon equipment");
                }
            }
        }

        uint fightBossFee = uint(game.usdToColos(game.getFightBossFee(bosses.getPower(boss))));
        require(colos.balanceOf(msg.sender) >= fightBossFee,
            string(abi.encodePacked("Not enough COLOS! Need ",RandomUtil.uint2str(fightBossFee))));
        _;
    }

    function startRaid() public restricted {
        for(uint8 i = 1; i <= 30; i++) {
            _startRaid(i);
        }
    }

    function startRaid1() public restricted {
        for(uint8 i = 1; i <= 10; i++) {
            _startRaid(i);
        }
    }

    function startRaid2() public restricted {
        for(uint8 i = 11; i <= 20; i++) {
            _startRaid(i);
        }
    }

    function startRaid3() public restricted {
        for(uint8 i = 21; i <= 30; i++) {
            _startRaid(i);
        }
    }

    function startRaidId(uint8 raidLevel) public restricted {
        _startRaid(raidLevel);
    }

    function _startRaid(uint8 raidLevel) internal {
        uint maxLevel = uint(raidLevel + 1);
        uint minLevel = maxLevel;
        if(raidLevel >= 30) {
            maxLevel = 9999999;
            minLevel = 31;
        }
        uint256[] memory bossIds = bosses.getBossesByLevel(minLevel, maxLevel);

        uint256 seed = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1))));
        uint _bossIdsIndex = RandomUtil.combineSeeds(now, seed) % bossIds.length;
        uint _boss = bossIds[_bossIdsIndex];

        // HP reset
        bosses.setHP(_boss, bosses.getMaxHP(_boss));
        bosses.setInFight(_boss, true);

        raidBossIds[raidLevel] = _boss;
    }

    function getMyBoss(uint256 char, uint256[] memory itemIds) public view returns (uint256) {
        uint8 raidLevel = _getMyRaidLevel(char, itemIds);
        return raidBossIds[raidLevel];
    }

    function _getMyRaidLevel(uint256 char, uint256[] memory itemIds) internal view returns (uint8) {
        uint fixPower = characters.getFixPower(char, itemIds, msg.sender);
        uint8 raidLevel = uint8(fixPower.div(100).div(2));
        if(raidLevel >= 30) {
            raidLevel = 30;
        }
        return raidLevel;
    }

    //==============================================================================//
    // Fight at Boss
    //==============================================================================//
    function fightBoss(uint256 _char, uint256[] calldata _itemIds, uint256 _boss)
                  external fightModifierChecks(_char, _itemIds, _boss){
        uint256 char = _char;
        uint256[] memory itemIds = _itemIds;
        uint256 boss = _boss;

        uint beforeFightBossHP = bosses.getHP(boss);

        int128 fightBossFee = game.getFightBossFee(bosses.getPower(boss));
        game.payContract(msg.sender, fightBossFee);

        bool win;
        int256 totalDamage;
        (win, totalDamage) = _fightBossDetail(char, itemIds, boss);

        if (win) {
            // Win
            characters.setLastFightBossTimestamp(char, now);
            characters.incrementWinCountBoss(char);
            if(bosses.getOwnedByAdmin(boss) == false) {
                bosses.incrementLoseCount(boss);
            }

            uint256 rewardSkill = getRewardSkill(boss, totalDamage, beforeFightBossHP);
            uint256 rewardColos = getRewardColos(bosses.getPower(boss));
            game.skillToPlayer(msg.sender, rewardSkill);
            game.payPlayerConverted(msg.sender, rewardColos);

            emit FightOutcome(msg.sender, true, char, characters.getFixPower(char, itemIds, msg.sender), bosses.getPower(boss), bosses.getHP(boss), rewardSkill, rewardColos);
            bosses.setInFight(boss, false);
            _startRaid(_getMyRaidLevel(char, itemIds));
        } else {
            // lose (boss win)
            characters.setLastFightBossTimestamp(char, now);
            bosses.setLastFightTimestamp(boss, now);
            bosses.incrementWinCount(boss);
            uint256 rewardSkill = 0;
            if(totalDamage > 0) {
                rewardSkill = getRewardSkill(boss, totalDamage, beforeFightBossHP);
                game.skillToPlayer(msg.sender, rewardSkill);
            }
            // Reward the boss owner
            if(bosses.ownerOf(boss) != address(game)) {
                uint gainSkill = uint(game.usdToColos(fightBossFee)).div(2);
                game.skillToPlayer(bosses.ownerOf(boss), gainSkill);
                bosses.addTotalGain(boss, gainSkill);
            }

            emit FightOutcome(msg.sender, false, char, characters.getPower(char), bosses.getPower(boss), bosses.getHP(boss), rewardSkill, 0);
        }
    }

    function _fightBossDetail(uint256 _char, uint256[] memory _itemIds, uint256 _boss) internal returns (bool win, int256 totalDamage) {
        uint256 char = _char;
        uint256[] memory itemIds = _itemIds;
        uint256 boss = _boss;
        uint[] memory fixParams = characters.getFixParams(char, itemIds, msg.sender);
        Parameters memory player = Parameters(
            int256(fixParams[0]),
            fixParams[1],
            fixParams[2],
            fixParams[3],
            fixParams[4],
            fixParams[5]);
        Parameters memory target = Parameters(
            int256(bosses.getHP(boss)),
            bosses.getATK(boss),
            bosses.getDEF(boss),
            bosses.getSPD(boss),
            bosses.getLUK(boss),
            bosses.getPower(boss));

        int256 damage;
        uint state;
        bool prevTurnIsPlayer = true;
        for (uint turn = 1; player.HP > 0 && target.HP > 0; turn++) {
            if (turn == 1) {
                if ( 0 < SignedSafeMath.sub(int256(player.SPD), int256(target.SPD))) {
                    // player attack
                    (damage, state) = fight.attack(player.ATK, target.DEF, (int256(player.SPD) - int256(target.SPD)), player.LUK, turn);
                    target.HP = SignedSafeMath.sub(target.HP, damage);
                    totalDamage += damage;
                    prevTurnIsPlayer = true;
                    emit Attack(msg.sender, turn, damage, state);
                    continue;
                } else {
                    // target attack
                    (damage, state) = fight.attack(target.ATK, player.DEF, (int256(target.SPD) - int256(player.SPD)), target.LUK, turn);
                    player.HP = SignedSafeMath.sub(player.HP, damage);
                    prevTurnIsPlayer = false;
                    emit Damage(msg.sender, turn, damage, state);
                    continue;
                }
            }
            if (prevTurnIsPlayer) {
                // target attack
                (damage, state) = fight.attack(target.ATK, player.DEF, (int256(target.SPD) - int256(player.SPD)), target.LUK, turn);
                player.HP = SignedSafeMath.sub(player.HP, damage);
                prevTurnIsPlayer = false;
                emit Damage(msg.sender, turn, damage, state);
                continue;
            } else {
                // player attack
                (damage, state) = fight.attack(player.ATK, target.DEF, (int256(player.SPD) - int256(target.SPD)), player.LUK, turn);
                target.HP = SignedSafeMath.sub(target.HP, damage);
                totalDamage += damage;
                prevTurnIsPlayer = true;
                emit Attack(msg.sender, turn, damage, state);
                continue;
            }
        }
        if (player.HP <= 0) {
            bosses.setHP(_boss, uint(target.HP));
            // player lose
            win = false;
        } else {
            bosses.setHP(_boss, 0);
            // player win
            win = true;
        }
    }

    function getRewardSkill(uint256 boss, int256 totalDamage, uint beforeFightBossHP) public view returns (uint256) {
        return game.usdToColos(
            game.getFightBossFee(bosses.getPower(boss)).add(
                getSkillGainForFightBoss(totalDamage, beforeFightBossHP)));
    }

    function getSkillGainForFightBoss(int256 totalDamage, uint beforeFightBossHP) public view returns (int128) {
        return fightBossRewardGasOffset.add(
            fightBossRewardSkillBaseline.mul(
                    int128(uint(ABDKMath64x64.sqrt(
                        ABDKMath64x64.divu(uint(totalDamage), 1000))).div(2)
                )
            ).add(
            fightBossRewardSkillBaseline.mul(
                    int128(uint(ABDKMath64x64.sqrt(
                        ABDKMath64x64.divu(beforeFightBossHP, 1000)
                    )).div(2))
            ))
        );
    }

    function getRewardColos(uint targetPower) public view returns (uint256) {
        return game.usdToColos(getColosGainForFightBoss(targetPower));
    }

    function getColosGainForFightBoss(uint targetPower) public view returns (int128) {
        return fightBossRewardGasOffset.add(
            fightBossRewardColosBaseline.mul(
                ABDKMath64x64.sqrt(
                    ABDKMath64x64.divu(targetPower, 1000)
                )
            )
        );
    }

    function setFightBossRewardSkillBaselineValue(uint256 tenthcents) public restricted {
        fightBossRewardSkillBaseline = ABDKMath64x64.divu(tenthcents, 1000); // !!! THIS TAKES TENTH OF CENTS !!!
    }

    function setFightBossRewardColosBaselineValue(uint256 tenthcents) public restricted {
        fightBossRewardColosBaseline = ABDKMath64x64.divu(tenthcents, 1000); // !!! THIS TAKES TENTH OF CENTS !!!
    }

    function setFightBossRewardGasOffsetValue(uint256 cents) public restricted {
        fightBossRewardGasOffset = ABDKMath64x64.divu(cents, 100);
    }

    function getOwnedBossIds() public view returns(uint256[] memory) {
        uint256[] memory tokens = new uint256[](bosses.balanceOf(msg.sender));
        for(uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = bosses.tokenOfOwnerByIndex(msg.sender, i);
        }
        return tokens;
    }
}