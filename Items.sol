pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "./MasterColosseum.sol";
import "./Tickets.sol";
import "./util.sol";

contract Items is Initializable, ERC721Upgradeable, AccessControlUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeMathUpgradeable for uint128;
    using SafeMathUpgradeable for uint64;
    using SafeMathUpgradeable for uint16;
    using SafeMathUpgradeable for uint8;
    using ABDKMath64x64 for int128;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    uint256 public constant TICKET_BOSS_MINT = 1;
    uint256 public constant TICKET_ITEM_MINT = 2;

    MasterColosseum public game;

    mapping(uint256 => address) public ticketAddresses;
    mapping(uint256 => uint256) public ticketFlatPrices;

    struct Item {
        // 0-9:Weapon (0:Rod, 1:Axe, 2:Spear, 3:Knuckle, 4:Whip, 5:Sword)
        // 10-19:Armor (10:Shield, 11:Helm, 12:Armor, 13:Shoes)
        // 20-29:Accessory (20:Ring, 21:Necklace)
        uint8 kind;
        uint8 stars;
        int128 HP;
        int128 ATK;
        int128 DEF;
        int128 SPD;
        int128 LUK;
    }

    Item[] private tokens;
    uint256 private lastMintedBlock;
    uint256 private firstMintedOfLastBlock;
    mapping(uint256 => uint64) durabilityTimestamp;
    uint256 public constant maxDurability = 20;
    uint256 public constant secondsPerDurability = 3000; //50 * 60

    event NewItem(uint256 indexed item, address indexed minter);
    event BurnItem(uint256 indexed item, address indexed owner);

    function initialize () public initializer {
        __ERC721_init("ChainColosseum Item", "CCI");
        __AccessControl_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function migrate_ticket(MasterColosseum _game, address _bossMintTickets, address _itemMintTickets) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        game = _game;
        ticketAddresses[TICKET_BOSS_MINT] = _bossMintTickets;
        ticketFlatPrices[TICKET_BOSS_MINT] = 0.1 ether;
        ticketAddresses[TICKET_ITEM_MINT] = _itemMintTickets;
        ticketFlatPrices[TICKET_ITEM_MINT] = 1 ether;
    }

    modifier restricted() {
        _restricted();
        _;
    }

    function _restricted() internal view {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
    }

    modifier noFreshLookup(uint256 id) {
        _noFreshLookup(id);
        _;
    }

    function _noFreshLookup(uint256 id) internal view {
        require(id < firstMintedOfLastBlock || lastMintedBlock < block.number, "Too fresh for lookup");
    }

    function getStats(uint256 id) internal view
        returns (uint8 _kind, uint8 _stars, int128 _HP, int128 _ATK, int128 _DEF, int128 _SPD, int128 _LUK) {

        Item memory i = tokens[id];
        return (i.kind, i.stars, i.HP, i.ATK, i.DEF, i.SPD, i.LUK);
    }

    function get(uint256 id) public view
        returns (
            uint8 _kind, uint8 _stars, int128 _HP, int128 _ATK, int128 _DEF, int128 _SPD, int128 _LUK, int128 _Power
    ) {
        (_kind, _stars, _HP, _ATK, _DEF, _SPD, _LUK) = getStats(id);
        _Power = getPower(id);
    }

    function mint(address minter, uint256 seed) public restricted returns(uint256) {
        // select kind
        uint8 kind;
        uint256 kindRoll = seed % 12;
        if(kindRoll == 0) kind = 0;
        if(kindRoll == 1) kind = 1;
        if(kindRoll == 2) kind = 2;
        if(kindRoll == 3) kind = 3;
        if(kindRoll == 4) kind = 4;
        if(kindRoll == 5) kind = 5;
        if(kindRoll == 6) kind = 10;
        if(kindRoll == 7) kind = 11;
        if(kindRoll == 8) kind = 12;
        if(kindRoll == 9) kind = 13;
        if(kindRoll == 10) kind = 20;
        if(kindRoll == 11) kind = 21;
        // select stars
        uint8 stars;
        uint256 roll = seed % 1000;
        if(roll < 8) {
            stars = 4; // 5* at 0.8%
        }
        else if(roll < 30) { // 4* at 2.2%
            stars = 3;
        }
        else if(roll < 130) { // 3* at 10%
            stars = 2;
        }
        else if(roll < 430) { // 2* at 30%
            stars = 1;
        }
        else {
            stars = 0; // 1* at 57%
        }

        return mintItemWithStars(minter, kind, stars, seed);
    }

    function mintN(address minter, uint32 num, uint256 seed) public restricted returns(uint256[] memory) {
        require(num > 0 && num <= 50);
        uint256[] memory tokenIds = new uint256[](num);
        for (uint i = 0; i < num; i++) {
            uint256 tokenId = mint(minter, uint256(keccak256(abi.encodePacked(seed, i))));
            tokenIds[i] = tokenId;
        }
        return tokenIds;
    }

    function mintItemWithStars(address minter, uint8 kind, uint8 stars, uint256 seed) public restricted returns(uint256) {
        require(stars < 8, "Stars parameter too high! (max 7)");
        (int128 HP, int128 ATK, int128 DEF, int128 SPD, int128 LUK) = getRandomParameters(kind, stars, seed);

        return performMintItem(minter, kind, stars, HP, ATK, DEF, SPD, LUK);
    }

    function performMintItem(address minter,
        uint8 kind, uint8 stars, int128 HP, int128 ATK, int128 DEF, int128 SPD, int128 LUK
    ) public restricted returns(uint256) {

        uint256 tokenID = tokens.length;

        if(block.number != lastMintedBlock)
            firstMintedOfLastBlock = tokenID;
        lastMintedBlock = block.number;

        tokens.push(Item(kind, stars, HP, ATK, DEF, SPD, LUK));
        _mint(minter, tokenID);

        emit NewItem(tokenID, minter);
        return tokenID;
    }

    function getRandomParameters(uint8 kind, uint8 stars, uint256 seed) public pure
        returns (int128, int128, int128, int128, int128) {
        return (
            getRandomParameter(kind, stars, 0, seed), // HP
            getRandomParameter(kind, stars, 1, seed), // ATK
            getRandomParameter(kind, stars, 2, seed), // DEF
            getRandomParameter(kind, stars, 3, seed), // SPD
            getRandomParameter(kind, stars, 4, seed)  // LUK
        );
    }

    function getRandomParameter(uint8 kind, uint8 stars, uint8 parameter, uint256 seed) private pure returns (int128) {
        int128 minRoll = getStatMinRoll(kind, stars, parameter);
        int128 maxRoll = getStatMaxRoll(kind, stars, parameter);

        if (minRoll == 0 && maxRoll == 0) {
            return 0;
        }

        if (minRoll >= 0) {
            return int128(RandomUtil.randomSeededMinMax(uint256(minRoll), uint256(maxRoll), RandomUtil.combineSeeds(seed,parameter)));
        } else {
            minRoll = ABDKMath64x64.mul(minRoll, -1);
            if (maxRoll < 0) {
                maxRoll = ABDKMath64x64.mul(maxRoll, -1);
            }
            return ABDKMath64x64.mul(int128(RandomUtil.randomSeededMinMax(uint256(minRoll), uint256(maxRoll),RandomUtil.combineSeeds(seed,parameter))), -1);
        }
    }

    function getStatMinRoll(uint8 kind, uint8 stars, uint8 parameter) public pure returns (int128) {
        // 0-9:Weapon (0:Rod, 1:Axe, 2:Spear, 3:Knuckle, 4:Whip, 5:Sword)
        // Rod
        if (kind == 0) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 0;  // 1 stars
                if (stars == 1) return 10;  // 2 stars
                if (stars == 2) return 30; // 3 stars
                if (stars == 3) return 50; // 4 stars
                if (stars == 4) return 90; // 5 stars
                return 200;                // 6+ stars
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 8;  // 1 stars
                if (stars == 1) return 20;  // 2 stars
                if (stars == 2) return 56;  // 3 stars
                if (stars == 3) return 100; // 4 stars
                if (stars == 4) return 220; // 5 stars
                return 400;                // 6+ stars
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 0;  // 1 stars
                if (stars == 1) return 20;  // 2 stars
                if (stars == 2) return 40;  // 3 stars
                if (stars == 3) return 100; // 4 stars
                if (stars == 4) return 200; // 5 stars
                return 350;                // 6+ stars
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 0;  // 1 stars
                if (stars == 1) return 10;  // 2 stars
                if (stars == 2) return 20;  // 3 stars
                if (stars == 3) return 50; // 4 stars
                if (stars == 4) return 70; // 5 stars
                return 100;                // 6+ stars
            }
        }
        // Axe
        if (kind == 1) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 5;   // 1 stars
                if (stars == 1) return 10;  // 2 stars
                if (stars == 2) return 30;  // 3 stars
                if (stars == 3) return 70;  // 4 stars
                if (stars == 4) return 200; // 5 stars
                return 300;                // 6+ stars
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 16;  // 1 stars
                if (stars == 1) return 36;  // 2 stars
                if (stars == 2) return 90; // 3 stars
                if (stars == 3) return 200; // 4 stars
                if (stars == 4) return 400; // 5 stars
                return 600;                // 6+ stars
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 10;  // 1 stars
                if (stars == 1) return 25;  // 2 stars
                if (stars == 2) return 50;  // 3 stars
                if (stars == 3) return 120; // 4 stars
                if (stars == 4) return 250; // 5 stars
                return 400;                // 6+ stars
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 4;  // 1 stars
                if (stars == 1) return 10;  // 2 stars
                if (stars == 2) return 20;  // 3 stars
                if (stars == 3) return 50; // 4 stars
                if (stars == 4) return 70; // 5 stars
                return 100;                // 6+ stars
            }
        }
        // Spear
        if (kind == 2) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 0;   // 1 stars
                if (stars == 1) return 5;   // 2 stars
                if (stars == 2) return 20;  // 3 stars
                if (stars == 3) return 50;  // 4 stars
                if (stars == 4) return 100; // 5 stars
                return 200;                // 6+ stars
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 12;  // 1 stars
                if (stars == 1) return 32;  // 2 stars
                if (stars == 2) return 76; // 3 stars
                if (stars == 3) return 140; // 4 stars
                if (stars == 4) return 300; // 5 stars
                return 500;                // 6+ stars
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 20;  // 1 stars
                if (stars == 1) return 40;  // 2 stars
                if (stars == 2) return 86;  // 3 stars
                if (stars == 3) return 180; // 4 stars
                if (stars == 4) return 400; // 5 stars
                return 600;                // 6+ stars
            }
            if (parameter == 3) {          // SPD
                if (stars == 0) return 10;  // 1 stars
                if (stars == 1) return 30;  // 2 stars
                if (stars == 2) return 50;  // 3 stars
                if (stars == 3) return 70; // 4 stars
                if (stars == 4) return 100; // 5 stars
                return 200;                // 6+ stars
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 4;  // 1 stars
                if (stars == 1) return 10;  // 2 stars
                if (stars == 2) return 20;  // 3 stars
                if (stars == 3) return 50; // 4 stars
                if (stars == 4) return 70; // 5 stars
                return 100;                // 6+ stars
            }
        }
        // Knuckle
        if (kind == 3) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 5;   // 1 stars
                if (stars == 1) return 10;   // 2 stars
                if (stars == 2) return 30;  // 3 stars
                if (stars == 3) return 70;  // 4 stars
                if (stars == 4) return 200; // 5 stars
                return 300;                // 6+ stars
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 12;  // 1 stars
                if (stars == 1) return 32;  // 2 stars
                if (stars == 2) return 76; // 3 stars
                if (stars == 3) return 140; // 4 stars
                if (stars == 4) return 300; // 5 stars
                return 500;                // 6+ stars
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 8;  // 1 stars
                if (stars == 1) return 20;  // 2 stars
                if (stars == 2) return 40;  // 3 stars
                if (stars == 3) return 100; // 4 stars
                if (stars == 4) return 200; // 5 stars
                return 350;                // 6+ stars
            }
            if (parameter == 3) {          // SPD
                if (stars == 0) return 20;  // 1 stars
                if (stars == 1) return 40;  // 2 stars
                if (stars == 2) return 80;  // 3 stars
                if (stars == 3) return 140; // 4 stars
                if (stars == 4) return 250; // 5 stars
                return 450;                // 6+ stars
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 10;  // 1 stars
                if (stars == 1) return 20;  // 2 stars
                if (stars == 2) return 40;  // 3 stars
                if (stars == 3) return 60; // 4 stars
                if (stars == 4) return 80; // 5 stars
                return 120;                // 6+ stars
            }
        }
        // Whip
        if (kind == 4) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 0;   // 1 stars
                if (stars == 1) return 5;   // 2 stars
                if (stars == 2) return 20;  // 3 stars
                if (stars == 3) return 40;  // 4 stars
                if (stars == 4) return 80; // 5 stars
                return 150;                // 6+ stars
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 8;  // 1 stars
                if (stars == 1) return 20;  // 2 stars
                if (stars == 2) return 56; // 3 stars
                if (stars == 3) return 100; // 4 stars
                if (stars == 4) return 220; // 5 stars
                return 400;                // 6+ stars
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 4;  // 1 stars
                if (stars == 1) return 16;  // 2 stars
                if (stars == 2) return 30;  // 3 stars
                if (stars == 3) return 60; // 4 stars
                if (stars == 4) return 100; // 5 stars
                return 250;                // 6+ stars
            }
            if (parameter == 3) {          // SPD
                if (stars == 0) return 10;  // 1 stars
                if (stars == 1) return 30;  // 2 stars
                if (stars == 2) return 50;  // 3 stars
                if (stars == 3) return 70; // 4 stars
                if (stars == 4) return 100; // 5 stars
                return 200;                // 6+ stars
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 4;  // 1 stars
                if (stars == 1) return 10;  // 2 stars
                if (stars == 2) return 20;  // 3 stars
                if (stars == 3) return 50; // 4 stars
                if (stars == 4) return 70; // 5 stars
                return 100;                // 6+ stars
            }
        }
        // Sword
        if (kind == 5) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 0;   // 1 stars
                if (stars == 1) return 5;   // 2 stars
                if (stars == 2) return 20;  // 3 stars
                if (stars == 3) return 50;  // 4 stars
                if (stars == 4) return 100; // 5 stars
                return 200;                // 6+ stars
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 20;  // 1 stars
                if (stars == 1) return 40;  // 2 stars
                if (stars == 2) return 100; // 3 stars
                if (stars == 3) return 250; // 4 stars
                if (stars == 4) return 500; // 5 stars
                return 700;                // 6+ stars
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 10;  // 1 stars
                if (stars == 1) return 25;  // 2 stars
                if (stars == 2) return 50;  // 3 stars
                if (stars == 3) return 120; // 4 stars
                if (stars == 4) return 250; // 5 stars
                return 400;                // 6+ stars
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                return 0;
            }
        }
        // 10:Shield, 11:Helm, 12:Armor, 13:Shoes
        // Shield
        if (kind == 10) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 2;   // 1 stars
                if (stars == 1) return 10;   // 2 stars
                if (stars == 2) return 22;  // 3 stars
                if (stars == 3) return 40;  // 4 stars
                if (stars == 4) return 60; // 5 star
                return 80;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 8;  // 1 star
                if (stars == 1) return 16;  // 2 star
                if (stars == 2) return 32;  // 3 star
                if (stars == 3) return 60; // 4 star
                if (stars == 4) return 100; // 5 star
                return 300;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                return 0;
            }
        }
        // Helm
        if (kind == 11) {
            if (parameter == 0) {          // HP
                return 0;
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 2;   // 1 stars
                if (stars == 1) return 10;   // 2 stars
                if (stars == 2) return 22;  // 3 stars
                if (stars == 3) return 40;  // 4 stars
                if (stars == 4) return 60; // 5 star
                return 80;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 2;   // 1 stars
                if (stars == 1) return 10;   // 2 stars
                if (stars == 2) return 22;  // 3 stars
                if (stars == 3) return 40;  // 4 stars
                if (stars == 4) return 60; // 5 star
                return 80;                // 6+ star
            }
        }
        // Armor
        if (kind == 12) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 2;   // 1 stars
                if (stars == 1) return 10;   // 2 stars
                if (stars == 2) return 22;  // 3 stars
                if (stars == 3) return 40;  // 4 stars
                if (stars == 4) return 60; // 5 star
                return 80;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 4;   // 1 stars
                if (stars == 1) return 14;   // 2 stars
                if (stars == 2) return 24;  // 3 stars
                if (stars == 3) return 40;  // 4 stars
                if (stars == 4) return 66; // 5 star
                return 90;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                return 0;
            }
        }
        // Shoes
        if (kind == 13) {
            if (parameter == 0) {          // HP
                return 0;
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 2;   // 1 stars
                if (stars == 1) return 10;   // 2 stars
                if (stars == 2) return 22;  // 3 stars
                if (stars == 3) return 40;  // 4 stars
                if (stars == 4) return 60; // 5 star
                return 80;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                if (stars == 0) return 8;  // 1 star
                if (stars == 1) return 16;  // 2 star
                if (stars == 2) return 32;  // 3 star
                if (stars == 3) return 60; // 4 star
                if (stars == 4) return 100; // 5 star
                return 300;                // 6+ star
            }
            if (parameter == 4) {          // LUK
                return 0;
            }
        }

        // 20:Ring, 21:Necklace
        // Ring
        if (kind == 20) {
            if (parameter == 0) {          // HP
                return 0;
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                return 0;
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 16;  // 1 star
                if (stars == 1) return 40;  // 2 star
                if (stars == 2) return 66;  // 3 star
                if (stars == 3) return 90; // 4 star
                if (stars == 4) return 120; // 5 star
                return 180;                // 6+ star
            }
        }
        // Necklace
        if (kind == 21) {
            if (parameter == 0) {          // HP
                return 0;
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                return 0;
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 16;  // 1 star
                if (stars == 1) return 40;  // 2 star
                if (stars == 2) return 66;  // 3 star
                if (stars == 3) return 90; // 4 star
                if (stars == 4) return 120; // 5 star
                return 180;                // 6+ star
            }
        }
    }

    function getStatMaxRoll(uint8 kind, uint8 stars, uint8 parameter) public pure returns (int128) {
        // Rod
        if (kind == 0) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 0;   // 1 star
                if (stars == 1) return 20;   // 2 star
                if (stars == 2) return 40;  // 3 star
                if (stars == 3) return 70;  // 4 star
                if (stars == 4) return 120; // 5 star
                return 300;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 16;  // 1 star
                if (stars == 1) return 36;  // 2 star
                if (stars == 2) return 80; // 3 star
                if (stars == 3) return 170; // 4 star
                if (stars == 4) return 330; // 5 star
                return 600;                // 6+ star
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 0;  // 1 star
                if (stars == 1) return 32;  // 2 star
                if (stars == 2) return 60;  // 3 star
                if (stars == 3) return 180; // 4 star
                if (stars == 4) return 300; // 5 star
                return 450;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 0;  // 1 star
                if (stars == 1) return 18;  // 2 star
                if (stars == 2) return 30;  // 3 star
                if (stars == 3) return 60; // 4 star
                if (stars == 4) return 80; // 5 star
                return 120;                // 6+ star
            }
        }
        // Axe
        if (kind == 1) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 8;   // 1 star
                if (stars == 1) return 20;   // 2 star
                if (stars == 2) return 50;  // 3 star
                if (stars == 3) return 120;  // 4 star
                if (stars == 4) return 280; // 5 star
                return 400;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 28;  // 1 star
                if (stars == 1) return 70;  // 2 star
                if (stars == 2) return 150; // 3 star
                if (stars == 3) return 300; // 4 star
                if (stars == 4) return 500; // 5 star
                return 800;                // 6+ star
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 20;  // 1 star
                if (stars == 1) return 45;  // 2 star
                if (stars == 2) return 80;  // 3 star
                if (stars == 3) return 200; // 4 star
                if (stars == 4) return 350; // 5 star
                return 600;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 8;  // 1 star
                if (stars == 1) return 18;  // 2 star
                if (stars == 2) return 30;  // 3 star
                if (stars == 3) return 60; // 4 star
                if (stars == 4) return 80; // 5 star
                return 120;                // 6+ star
            }
        }
        // Spear
        if (kind == 2) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 0;   // 1 star
                if (stars == 1) return 15;   // 2 star
                if (stars == 2) return 30;  // 3 star
                if (stars == 3) return 70;  // 4 star
                if (stars == 4) return 150; // 5 star
                return 300;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 28;  // 1 star
                if (stars == 1) return 50;  // 2 star
                if (stars == 2) return 100; // 3 star
                if (stars == 3) return 250; // 4 star
                if (stars == 4) return 430; // 5 star
                return 700;                // 6+ star
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 30;  // 1 star
                if (stars == 1) return 60;  // 2 star
                if (stars == 2) return 100;  // 3 star
                if (stars == 3) return 300; // 4 star
                if (stars == 4) return 500; // 5 star
                return 700;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                if (stars == 0) return 20;  // 1 star
                if (stars == 1) return 40;  // 2 star
                if (stars == 2) return 60;  // 3 star
                if (stars == 3) return 90; // 4 star
                if (stars == 4) return 150; // 5 star
                return 300;                // 6+ star
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 8;  // 1 star
                if (stars == 1) return 18;  // 2 star
                if (stars == 2) return 30;  // 3 star
                if (stars == 3) return 60; // 4 star
                if (stars == 4) return 80; // 5 star
                return 120;                // 6+ star
            }
        }
        // Knuckle
        if (kind == 3) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 8;   // 1 star
                if (stars == 1) return 20;   // 2 star
                if (stars == 2) return 50;  // 3 star
                if (stars == 3) return 120;  // 4 star
                if (stars == 4) return 280; // 5 star
                return 400;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 28;  // 1 star
                if (stars == 1) return 50;  // 2 star
                if (stars == 2) return 100; // 3 star
                if (stars == 3) return 250; // 4 star
                if (stars == 4) return 430; // 5 star
                return 700;                // 6+ star
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 18;  // 1 star
                if (stars == 1) return 35;  // 2 star
                if (stars == 2) return 60;  // 3 star
                if (stars == 3) return 180; // 4 star
                if (stars == 4) return 300; // 5 star
                return 450;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                if (stars == 0) return 30;  // 1 star
                if (stars == 1) return 60;  // 2 star
                if (stars == 2) return 100;  // 3 star
                if (stars == 3) return 200; // 4 star
                if (stars == 4) return 350; // 5 star
                return 600;                // 6+ star
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 18;  // 1 star
                if (stars == 1) return 30;  // 2 star
                if (stars == 2) return 50;  // 3 star
                if (stars == 3) return 70; // 4 star
                if (stars == 4) return 90; // 5 star
                return 140;                // 6+ star
            }
        }
        // Whip
        if (kind == 4) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 0;   // 1 star
                if (stars == 1) return 5;   // 2 star
                if (stars == 2) return 30;  // 3 star
                if (stars == 3) return 60;  // 4 star
                if (stars == 4) return 100; // 5 star
                return 200;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 16;  // 1 star
                if (stars == 1) return 36;  // 2 star
                if (stars == 2) return 80; // 3 star
                if (stars == 3) return 170; // 4 star
                if (stars == 4) return 330; // 5 star
                return 600;                // 6+ star
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 10;  // 1 star
                if (stars == 1) return 25;  // 2 star
                if (stars == 2) return 40;  // 3 star
                if (stars == 3) return 80; // 4 star
                if (stars == 4) return 200; // 5 star
                return 350;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                if (stars == 0) return 20;  // 1 star
                if (stars == 1) return 40;  // 2 star
                if (stars == 2) return 60;  // 3 star
                if (stars == 3) return 90; // 4 star
                if (stars == 4) return 150; // 5 star
                return 300;                // 6+ star
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 8;  // 1 star
                if (stars == 1) return 18;  // 2 star
                if (stars == 2) return 30;  // 3 star
                if (stars == 3) return 60; // 4 star
                if (stars == 4) return 80; // 5 star
                return 120;                // 6+ star
            }
        }
        // Sword
        if (kind == 5) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 0;   // 1 star
                if (stars == 1) return 15;   // 2 star
                if (stars == 2) return 30;  // 3 star
                if (stars == 3) return 70;  // 4 star
                if (stars == 4) return 150; // 5 star
                return 300;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                if (stars == 0) return 40;  // 1 star
                if (stars == 1) return 80;  // 2 star
                if (stars == 2) return 200; // 3 star
                if (stars == 3) return 400; // 4 star
                if (stars == 4) return 600; // 5 star
                return 1000;                // 6+ star
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 20;  // 1 star
                if (stars == 1) return 45;  // 2 star
                if (stars == 2) return 80;  // 3 star
                if (stars == 3) return 200; // 4 star
                if (stars == 4) return 350; // 5 star
                return 600;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                return 0;
            }
        }

        // 10:Shield, 11:Helm, 12:Armor, 13:Shoes
        // Shield
        if (kind == 10) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 8;   // 1 star
                if (stars == 1) return 16;   // 2 star
                if (stars == 2) return 36;  // 3 star
                if (stars == 3) return 50;  // 4 star
                if (stars == 4) return 70; // 5 star
                return 90;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 12;  // 1 star
                if (stars == 1) return 26;  // 2 star
                if (stars == 2) return 46;  // 3 star
                if (stars == 3) return 80; // 4 star
                if (stars == 4) return 200; // 5 star
                return 400;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                return 0;
            }
        }
        // Helm
        if (kind == 11) {
            if (parameter == 0) {          // HP
                return 0;
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 8;   // 1 star
                if (stars == 1) return 16;   // 2 star
                if (stars == 2) return 36;  // 3 star
                if (stars == 3) return 50;  // 4 star
                if (stars == 4) return 70; // 5 star
                return 90;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 8;   // 1 star
                if (stars == 1) return 16;   // 2 star
                if (stars == 2) return 36;  // 3 star
                if (stars == 3) return 50;  // 4 star
                if (stars == 4) return 70; // 5 star
                return 90;                // 6+ star
            }
        }
        // Armor
        if (kind == 12) {
            if (parameter == 0) {          // HP
                if (stars == 0) return 8;   // 1 star
                if (stars == 1) return 16;   // 2 star
                if (stars == 2) return 36;  // 3 star
                if (stars == 3) return 50;  // 4 star
                if (stars == 4) return 70; // 5 star
                return 90;                // 6+ star
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 10;  // 1 star
                if (stars == 1) return 20;  // 2 star
                if (stars == 2) return 30;  // 3 star
                if (stars == 3) return 56; // 4 star
                if (stars == 4) return 80; // 5 star
                return 100;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                return 0;
            }
        }
        // Shoes
        if (kind == 13) {
            if (parameter == 0) {          // HP
                return 0;
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                if (stars == 0) return 8;   // 1 star
                if (stars == 1) return 16;   // 2 star
                if (stars == 2) return 36;  // 3 star
                if (stars == 3) return 50;  // 4 star
                if (stars == 4) return 70; // 5 star
                return 90;                // 6+ star
            }
            if (parameter == 3) {          // SPD
                if (stars == 0) return 12;   // 1 star
                if (stars == 1) return 26;   // 2 star
                if (stars == 2) return 46;  // 3 star
                if (stars == 3) return 80;  // 4 star
                if (stars == 4) return 200; // 5 star
                return 400;                // 6+ star
            }
            if (parameter == 4) {          // LUK
                return 0;
            }
        }

        // 20:Ring, 21:Necklace
        // Ring
        if (kind == 20) {
            if (parameter == 0) {          // HP
                return 0;
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                return 0;
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 28;   // 1 star
                if (stars == 1) return 56;   // 2 star
                if (stars == 2) return 80;  // 3 star
                if (stars == 3) return 100;  // 4 star
                if (stars == 4) return 160; // 5 star
                return 220;                // 6+ star
            }
        }
        // Necklace
        if (kind == 21) {
            if (parameter == 0) {          // HP
                return 0;
            }
            if (parameter == 1) {          // ATK
                return 0;
            }
            if (parameter == 2) {          // DEF
                return 0;
            }
            if (parameter == 3) {          // SPD
                return 0;
            }
            if (parameter == 4) {          // LUK
                if (stars == 0) return 28;   // 1 star
                if (stars == 1) return 56;   // 2 star
                if (stars == 2) return 80;  // 3 star
                if (stars == 3) return 100;  // 4 star
                if (stars == 4) return 160; // 5 star
                return 220;                // 6+ star
            }
        }
    }

    function getKind(uint256 id) public view returns (uint8) {
        return tokens[id].kind;
    }

    function getStars(uint256 id) public view returns (uint8) {
        return tokens[id].stars;
    }

    function getHP(uint256 id) public view returns (int128) {
        return tokens[id].HP;
    }

    function getATK(uint256 id) public view returns (int128) {
        return tokens[id].ATK;
    }

    function getDEF(uint256 id) public view returns (int128) {
        return tokens[id].DEF;
    }

    function getSPD(uint256 id) public view returns (int128) {
        return tokens[id].SPD;
    }

    function getLUK(uint256 id) public view returns (int128) {
        return tokens[id].LUK;
    }

    function getPower(uint256 id) public view returns (int128) {
        return (tokens[id].HP + tokens[id].ATK + tokens[id].DEF + tokens[id].SPD + tokens[id].LUK);
    }

    function burn(uint256 burnID) public restricted {
        address burnOwner = ownerOf(burnID);
        _burn(burnID);

        emit BurnItem(burnID, burnOwner);
    }

    function getAddressOfTicket(uint256 ticketIndex) public view returns(address) {
        return ticketAddresses[ticketIndex];
    }

    function getFlatPriceOfTicket(uint256 ticketIndex) public view returns(uint256) {
        return ticketFlatPrices[ticketIndex];
    }

    function setBossMintTicketPrice(uint256 newPrice) external restricted {
        require(newPrice > 0, 'invalid price');
        ticketFlatPrices[TICKET_BOSS_MINT] = newPrice;
    }

    function bossMintTicketPrice() public view returns (uint256){
        return ticketFlatPrices[TICKET_BOSS_MINT];
    }

    function purchaseBossMintTicket(uint256 buyAmount) public {
        game.skillToContract(msg.sender, buyAmount.mul(ticketFlatPrices[TICKET_BOSS_MINT]));
        Tickets(ticketAddresses[TICKET_BOSS_MINT]).giveTicket(msg.sender, buyAmount);
    }

    function giveBossMintTicket(address taker, uint256 amount) public restricted {
        Tickets(ticketAddresses[TICKET_BOSS_MINT]).giveTicket(taker, amount);
    }

    function setItemMintTicketPrice(uint256 newPrice) external restricted {
        require(newPrice > 0, 'invalid price');
        ticketFlatPrices[TICKET_ITEM_MINT] = newPrice;
    }

    function itemMintTicketPrice() public view returns (uint256){
        return ticketFlatPrices[TICKET_ITEM_MINT];
    }

    function purchaseItemMintTicket(uint256 paying) public {
        require(paying == ticketFlatPrices[TICKET_ITEM_MINT], 'Invalid price');
        game.payContractConverted(msg.sender, ticketFlatPrices[TICKET_ITEM_MINT]);
        Tickets(ticketAddresses[TICKET_ITEM_MINT]).giveTicket(msg.sender, 1);
    }

    function giveItemMintTicket(address taker, uint256 amount) public restricted {
        Tickets(ticketAddresses[TICKET_ITEM_MINT]).giveTicket(taker, amount);
    }
}
