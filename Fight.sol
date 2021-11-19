// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";

import "./interfaces/IRandoms.sol";
import "./ColosToken.sol";
import "./MasterColosseum.sol";
import "./Characters.sol";
import "./Items.sol";
import "./util.sol";

contract Fight is Initializable, AccessControlUpgradeable {
    using SignedSafeMath for int256;
    using SafeMath for uint;
    using SafeMath for uint256;
    using SafeMath for uint64;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    ColosToken public colos;
    MasterColosseum public game;
    Characters public characters;
    Items public items;
    IRandoms public randoms;

    mapping(address => uint256) lastBlockNumberCalled;

    struct Parameters {
        int256 HP;
        uint ATK;
        uint DEF;
        uint SPD;
        uint LUK;
        uint Power;
    }

    event Attack(address indexed user, uint turn, int256 damage, uint state); // state: 0:miss, 1:normal, 2:critical
    event Damage(address indexed user, uint turn, int256 damage, uint state); // state: 0:miss, 1:normal, 2:critical
    event FightOutcome(address indexed owner, bool win, uint256 indexed character, uint256 playerPower, uint256 targetPower, uint256 tokenGain);

    function initialize(
        ColosToken _colos,
        MasterColosseum _game,
        Characters _characters,
        Items _items,
        IRandoms _randoms
    ) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GAME_ADMIN, msg.sender);

        colos = _colos;
        game = _game;
        characters = _characters;
        items = _items;
        randoms = _randoms;
    }

    modifier restricted() {
        require(hasRole(GAME_ADMIN, msg.sender), "Missing GAME_ADMIN role");
        _;
    }

        modifier fightModifierChecks(uint256 char, uint256[] memory itemIds, uint[] memory targetParams) {
        require(tx.origin == msg.sender, "Only EOA allowed (temporary)");
        // require(characters.balanceOf(msg.sender) <= characters.characterLimit(), "Too many characters owned");
        require(lastBlockNumberCalled[msg.sender] < block.number, "Only callable once per block");
        lastBlockNumberCalled[msg.sender] = block.number;
        require(characters.ownerOf(char) == msg.sender, "Not the character owner");
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

        uint targetPower = (targetParams[0] + targetParams[1] + targetParams[2] + targetParams[3] + targetParams[4]);
        uint fightFee = uint(game.usdToColos(game.getFightFee(targetPower)));
        require(colos.balanceOf(msg.sender) >= fightFee,
            string(abi.encodePacked("Not enough COLOS! Need ",RandomUtil.uint2str(fightFee))));
        _;
    }

    //==============================================================================//
    // Fight at Colosseum
    //==============================================================================//
    function fight(uint256 _char, uint256[] calldata _itemIds, string calldata _round, uint[] calldata _targetParams)
        external fightModifierChecks(_char, _itemIds, _targetParams){
        uint256 char = _char;
        uint256[] memory itemIds = _itemIds;
        string memory round = _round;
        uint[] memory targetParams = _targetParams;
        if (keccak256(abi.encodePacked(round)) == keccak256(abi.encodePacked("First"))) {
            require(characters.canFight(char) == true, "this character can't fight in first round");
        }
        uint targetPower = (targetParams[0] + targetParams[1] + targetParams[2] + targetParams[3] + targetParams[4]);
        int128 fightFee = game.getFightFee(targetPower);
        game.payContract(msg.sender, fightFee);

        Parameters memory target = Parameters(int256(targetParams[0]), targetParams[1], targetParams[2], targetParams[3], targetParams[4], targetPower);

        if (_fightDetail(char, itemIds, target)) {
            // win
            characters.setLastFightTimestamp(char, now);
            uint256 tokens = game.usdToColos(game.getTokenGainForFight(targetPower));
            // SKILLゲット
            game.skillToPlayer(msg.sender, tokens);

            if (keccak256(abi.encodePacked(round)) == keccak256(abi.encodePacked("First"))) {
                characters.setFightRound(char, 1);
                characters.incrementWinCountFirst(char);
            } else if (keccak256(abi.encodePacked(round)) == keccak256(abi.encodePacked("Second"))) {
                characters.setFightRound(char, 2);
                characters.incrementWinCountSecond(char);
            } else if (keccak256(abi.encodePacked(round)) == keccak256(abi.encodePacked("Third"))) {
                characters.setFightRound(char, 0);
                characters.incrementWinCountThird(char);
                // get COLOS
                game.payPlayerConverted(msg.sender, tokens);
            }
            emit FightOutcome(msg.sender, true, char, characters.getFixPower(char, itemIds, msg.sender), targetPower, tokens);
        } else {
            // lose
            characters.setLastFightTimestamp(char, now);
            characters.setFightRound(char, 0);
            emit FightOutcome(msg.sender, false, char, characters.getPower(char), targetPower, 0);
        }
    }

    function _fightDetail(uint256 _char, uint256[] memory _itemIds, Parameters memory target) internal returns (bool) {
        uint256 char = _char;
        uint256[] memory itemIds = _itemIds;
        uint[] memory fixParams = characters.getFixParams(char, itemIds, msg.sender);
        Parameters memory player = Parameters(
            int256(fixParams[0]),
            fixParams[1],
            fixParams[2],
            fixParams[3],
            fixParams[4],
            fixParams[5]);
        int256 damage;
        uint state;
        bool prevTurnIsPlayer = true;
        for (uint turn = 1; player.HP > 0 && target.HP > 0; turn++) {
            if (turn == 1) {
                if ( 0 < SignedSafeMath.sub(int256(player.SPD), int256(target.SPD))) {
                    // player attack
                    (damage, state) = attack(player.ATK, target.DEF, (int256(player.SPD) - int256(target.SPD)), player.LUK, turn);
                    target.HP = SignedSafeMath.sub(target.HP, damage);
                    prevTurnIsPlayer = true;
                    emit Attack(msg.sender, turn, damage, state);
                    continue;
                } else {
                    // target attack
                    (damage, state) = attack(target.ATK, player.DEF, (int256(target.SPD) - int256(player.SPD)), target.LUK, turn);
                    player.HP = SignedSafeMath.sub(player.HP, damage);
                    prevTurnIsPlayer = false;
                    emit Damage(msg.sender, turn, damage, state);
                    continue;
                }
            }

            if (prevTurnIsPlayer) {
                // target attack
                (damage, state) = attack(target.ATK, player.DEF, (int256(target.SPD) - int256(player.SPD)), target.LUK, turn);
                player.HP = SignedSafeMath.sub(player.HP, damage);
                prevTurnIsPlayer = false;
                emit Damage(msg.sender, turn, damage, state);
                continue;
            } else {
                // player attack
                (damage, state) = attack(player.ATK, target.DEF, (int256(player.SPD) - int256(target.SPD)), player.LUK, turn);
                target.HP = SignedSafeMath.sub(target.HP, damage);
                prevTurnIsPlayer = true;
                emit Attack(msg.sender, turn, damage, state);
                continue;
            }
        }
        if (player.HP <= 0) {
            // player lose
            return false;
        } else {
            // player win
            return true;
        }
    }

    function sqrt(uint x) public pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function attack(uint atk, uint def, int256 spdSub, uint luk, uint turn) public view returns (int256, uint) {
        int256 damage = 0;

        // Critical
        {
            uint base = 1000;
            uint _sqrt = sqrt(base.mul(base).div(sqrt(luk)));
            uint criticalRatio = luk.mul(_sqrt).div(base);
            uint rand = RandomUtil.combineSeeds(now, turn) % base;
            if(rand < criticalRatio) {
                // Critical hit: ignore DEF and damage 1.5 times more attack power
                damage = int256(atk.div(2).mul(3));
                // random additional damage
                damage = SignedSafeMath.add(damage, int256(RandomUtil.randomSeededMinMax(1,10,now.add(turn))));
                return (damage, 2);
            }
        }
        // avoid
        if (spdSub < 0) {
            spdSub = SignedSafeMath.mul(spdSub, -1);
            uint base = 1000;
            uint _sqrt = sqrt(base.mul(base).div(sqrt(uint(spdSub))));
            uint avoidRatio = uint(spdSub).mul(_sqrt).div(base);
            uint rand = RandomUtil.combineSeeds(now, turn) % base;
            if(rand < avoidRatio) {
                damage = 0;
                return (damage, 0);
            }
        }

        // damage
        // base = atk / 2 - def / 4
        damage = SignedSafeMath.sub(int256(atk.div(2)), int256(def.div(4)));
        // int256 damage = int256(atk.div(2));
        if (damage < 0) {
            damage = 0;
        }

        // random additional damage
        // range = base / 16 + 2
        uint damageBand = uint(damage).div(16).add(2);
        damage = SignedSafeMath.add(damage, int256(RandomUtil.randomSeededMinMax(1,damageBand,now.add(turn))));

        return (damage, 1);
    }

    function getTarget(uint256 _char, string memory round) public view returns (uint, uint, uint, uint, uint) {
        uint256 char = _char;
        uint playerPower = characters.getSkillPower(char, msg.sender);
        uint targetPower;
        if (keccak256(abi.encodePacked(round)) == keccak256(abi.encodePacked("First"))) {
            // Enemies in the first round change every hour
            uint256 seed = RandomUtil.combineSeeds(
                RandomUtil.combineSeeds(characters.getLastFightTimestamp(char), getCurrentHour()),
                playerPower);
            targetPower = RandomUtil.plusMinus10PercentSeeded(playerPower.add(86), seed);
        } else if (keccak256(abi.encodePacked(round)) == keccak256(abi.encodePacked("Second"))) {
            // The enemy of the second round does not change over time
            uint256 seed = RandomUtil.combineSeeds(characters.getLastFightTimestamp(char), playerPower);
            targetPower = RandomUtil.plusMinus10PercentSeeded(playerPower.add(225), seed);
        } else if (keccak256(abi.encodePacked(round)) == keccak256(abi.encodePacked("Third"))) {
            // The enemy of the third round does not change over time
            uint256 seed = RandomUtil.combineSeeds(characters.getLastFightTimestamp(char), playerPower);
            targetPower = RandomUtil.plusMinus10PercentSeeded(playerPower.add(472), seed);
        }
        return _targetRandomParameter(targetPower);
    }

    function _targetRandomParameter(uint256 targetPower) internal view returns (uint, uint, uint, uint, uint) {
        uint HP = 100;
        uint ATK = 50;
        uint DEF = 40;
        uint SPD = 30;
        uint LUK = 10;
        uint256 seed = RandomUtil.combineSeeds(getCurrentHour(), targetPower);
        uint pow = (HP+ATK+DEF+SPD+LUK);
        for (uint i = 0; pow < targetPower; i++ ){
            uint rand = uint(RandomUtil.randomSeededMinMax(1,5,seed+i));
            if (rand == 1) {
                HP += 1;
            } else if (rand == 2) {
                ATK += 1;
            } else if (rand == 3) {
                DEF += 1;
            } else if (rand == 4) {
                SPD += 1;
            } else if (rand == 5) {
                LUK += 1;
            }
            pow = (HP+ATK+DEF+SPD+LUK);
        }
        return (HP, ATK, DEF, SPD, LUK);
    }

    function getCurrentHour() public view returns (uint256) {
        return now.div(1 hours);
    }

}
