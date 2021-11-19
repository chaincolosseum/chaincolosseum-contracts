// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";

import "./interfaces/IPriceOracle.sol";
import "./interfaces/IRandoms.sol";
import "./ColosToken.sol";
import "./SkillToken.sol";
import "./Characters.sol";
import "./Items.sol";
import "./Fight.sol";
import "./util.sol";

contract MasterColosseum is Initializable, AccessControlUpgradeable {
    using ABDKMath64x64 for int128;
    using SafeMath for uint;
    using SafeMath for uint256;
    using SafeMath for uint64;
    using SafeERC20 for IERC20;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    ColosToken public colos;
    SkillToken public skill;
    Characters public characters;
    Items public items;
    Fight public fight;
    IPriceOracle public priceOracleColosPerUsd;
    int128 public mintCharacterFee;
    int128 public advancedCharacterJobFee;
    int128 public mintItemFee;
    int128 public mintItemNFee;
    int128 public fightFeeBaseline;
    int128 public fightBossFeeBaseline;
    mapping(address => uint256) lastBlockNumberCalled;
    IRandoms public randoms;
    int128 public fightRewardBaseline;
    int128 public fightRewardGasOffset;

    struct Parameters {
        int128 HP;
        uint ATK;
        uint DEF;
        uint SPD;
        uint LUK;
        uint Power;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function initialize(
        ColosToken _colos,
        SkillToken _skill,
        Characters _characters,
        Items _items,
        IPriceOracle _priceOracleColosPerUsd,
        IRandoms _randoms
    ) public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GAME_ADMIN, msg.sender);

        colos = _colos;
        skill = _skill;
        characters = _characters;
        items = _items;
        priceOracleColosPerUsd = _priceOracleColosPerUsd;
        randoms = _randoms;

        mintCharacterFee = ABDKMath64x64.divu(100, 1); // 100 usd;
        advancedCharacterJobFee = ABDKMath64x64.divu(1000, 1); // 1000 usd;
        mintItemFee = ABDKMath64x64.divu(20, 1); // 20 usd;
        mintItemNFee = ABDKMath64x64.divu(200, 1); // 200 usd;
        fightFeeBaseline = ABDKMath64x64.divu(80, 100); // 80 cent;
        fightBossFeeBaseline = ABDKMath64x64.divu(80, 100); // 80 cent;
        fightRewardGasOffset = ABDKMath64x64.divu(23177, 100000); // 0.0539 x 4.3
        fightRewardBaseline = ABDKMath64x64.divu(3300, 1000);
    }

    function migrate_fight(Fight _fight) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        fight = _fight;
    }

    modifier restricted() {
        require(hasRole(GAME_ADMIN, msg.sender), "Missing GAME_ADMIN role");
        _;
    }

    modifier onlyNonContract() {
        _onlyNonContract();
        _;
    }

    function _onlyNonContract() internal view {
        require(tx.origin == msg.sender, "Only EOA allowed (temporary)");
    }

    modifier oncePerBlock(address user) {
        require(lastBlockNumberCalled[user] < block.number, "Only callable once per block");
        lastBlockNumberCalled[user] = block.number;
        _;
    }

    modifier isCharacterOwner(uint256 character) {
        require(characters.ownerOf(character) == msg.sender, "Not the character owner");
        _;
    }

    modifier isItemsOwner(uint256[] memory itemIds) {
        for (uint i = 0; i < itemIds.length; i++) {
            require(items.ownerOf(itemIds[i]) == msg.sender, "Not the item owner");
        }
        _;
    }

    modifier requestPayFromPlayer(int128 usdAmount) {
        uint256 colosAmount = usdToColos(usdAmount);

        require(colos.balanceOf(msg.sender) >= colosAmount,
            string(abi.encodePacked("Not enough COLOS! Need ",RandomUtil.uint2str(colosAmount))));
        _;
    }

    modifier requestSkillFromPlayer(uint256 useSkillAmount) {
        require(skill.balanceOf(msg.sender) >= useSkillAmount, "insufficient skills");
        _;
    }

    function getMyCharacters() public view returns(uint256[] memory) {
        uint256[] memory tokens = new uint256[](characters.balanceOf(msg.sender));
        for(uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = characters.tokenOfOwnerByIndex(msg.sender, i);
        }
        return tokens;
    }

    function getMyItems() public view returns(uint256[] memory) {
        uint256[] memory tokens = new uint256[](items.balanceOf(msg.sender));
        for(uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = items.tokenOfOwnerByIndex(msg.sender, i);
        }
        return tokens;
    }

    function mintCharacter() public oncePerBlock(msg.sender) requestPayFromPlayer(mintCharacterFee) {
        _payContract(msg.sender, mintCharacterFee);
        uint256 seed = randoms.getRandomSeed(msg.sender);
        characters.mint(msg.sender, seed);

        if(items.balanceOf(msg.sender) == 0) {
            items.mintItemWithStars(msg.sender,
                0, // Rod
                0,
                RandomUtil.combineSeeds(seed,100)
            );
        }
    }

    function boostCharacter(uint256 char, uint256 useSkillAmount) public isCharacterOwner(char) oncePerBlock(msg.sender) requestSkillFromPlayer(useSkillAmount) {
        characters.boost(char, msg.sender, useSkillAmount);
        _skillToContract(msg.sender, useSkillAmount.mul(1 ether));
    }

    // function advancedCharacterJob(uint256 char) public isCharacterOwner(char) oncePerBlock(msg.sender) requestPayFromPlayer(advancedCharacterJobFee) {
    //     _payContract(msg.sender, advancedCharacterJobFee);
    //     characters.advancedJob(char, msg.sender);
    // }

    function mintItem() public onlyNonContract oncePerBlock(msg.sender) requestPayFromPlayer(mintItemFee) {
        _payContract(msg.sender, mintItemFee);
        items.mint(msg.sender, uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender))));
    }

    // function mintItemN() public onlyNonContract oncePerBlock(msg.sender) requestPayFromPlayer(mintItemNFee) {
    //     _payContract(msg.sender, mintItemNFee);
    //     items.mintN(msg.sender, 11, uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender))));
    // }

    // function burnItemN(uint256[] memory itemIds) public isItemsOwner(itemIds) oncePerBlock(msg.sender) {
    //     require(itemIds.length > 0);
    //     uint256 totalStars = 0;
    //     for (uint i = 0; i < itemIds.length; i++ ){
    //         totalStars = totalStars + items.getStars(itemIds[i]) + 1;
    //         items.burn(itemIds[i]);
    //     }
    //     uint256 num = totalStars.div(10);
    //     items.giveItemMintTicket(msg.sender, num);
    // }

    function payContract(address playerAddress, int128 usdAmount) public restricted {
        _payContract(playerAddress, usdAmount);
    }

    function payContractConverted(address playerAddress, uint256 convertedAmount) public restricted {
        _payContractConverted(playerAddress, convertedAmount);
    }

    function _payContract(address playerAddress, int128 usdAmount) internal {
        _payContractConverted(playerAddress, usdToColos(usdAmount));
    }

    function _payContractConverted(address playerAddress, uint256 convertedAmount) internal {
        colos.burnFrom(playerAddress, convertedAmount);
    }

    function payPlayer(address playerAddress, int128 baseAmount) public restricted {
        _payPlayer(playerAddress, baseAmount);
    }

    function payPlayerConverted(address playerAddress, uint256 convertedAmount) public restricted {
        _payPlayerConverted(playerAddress, convertedAmount);
    }

    function _payPlayer(address playerAddress, int128 baseAmount) internal {
        _payPlayerConverted(playerAddress, usdToColos(baseAmount));
    }

    function _payPlayerConverted(address playerAddress, uint256 convertedAmount) internal {
        colos.mint(playerAddress, convertedAmount);
    }

    function skillToContract(address playerAddress, uint256 skillAmount) public restricted {
        _skillToContract(playerAddress, skillAmount);
    }

    function _skillToContract(address playerAddress, uint256 skillAmount) internal {
        skill.burnFrom(playerAddress, skillAmount);
    }

    function skillToPlayer(address playerAddress, uint256 skillAmount) public restricted {
        skill.mint(playerAddress, skillAmount);
    }

    function usdToColos(int128 usdAmount) public view returns (uint256) {
        return usdAmount.mulu(priceOracleColosPerUsd.currentPrice());
    }

    function setCharacterMintValue(uint256 cents) public restricted {
        mintCharacterFee = ABDKMath64x64.divu(cents, 100);
    }

    function setFightRewardBaselineValue(uint256 tenthcents) public restricted {
        fightRewardBaseline = ABDKMath64x64.divu(tenthcents, 1000); // !!! THIS TAKES TENTH OF CENTS !!!
    }

    function setFightRewardGasOffsetValue(uint256 cents) public restricted {
        fightRewardGasOffset = ABDKMath64x64.divu(cents, 100);
    }

    function setMintCharacterFee(uint256 value) public restricted {
        mintCharacterFee = ABDKMath64x64.divu(value, 1);
    }

    function setAdvancedCharacterJobFee(uint256 value) public restricted {
        advancedCharacterJobFee = ABDKMath64x64.divu(value, 1);
    }

    function setItemMintValue(uint256 cents) public restricted {
        mintItemFee = ABDKMath64x64.divu(cents, 100);
        mintItemNFee = ABDKMath64x64.divu(cents.mul(10), 100);
    }

    function setFightFeeBaselineValue(uint256 cents) public restricted {
        fightFeeBaseline = ABDKMath64x64.divu(cents, 100);
    }

    function getFightFee(uint targetPower) public view returns (int128) {
        return fightFeeBaseline.add(
            fightFeeBaseline.mul(
                ABDKMath64x64.sqrt(
                    ABDKMath64x64.divu(targetPower, 1000)
                )
            )
        );
    }

    function getFightBossFee(uint targetPower) public view returns (int128) {
        return fightBossFeeBaseline.add(
            fightBossFeeBaseline.mul(
                ABDKMath64x64.sqrt(
                    ABDKMath64x64.divu(targetPower, 1000)
                )
            )
        );
    }

    function getTokenGainForFight(uint targetPower) public view returns (int128) {
        return fightRewardGasOffset.add(
            fightRewardBaseline.mul(
                ABDKMath64x64.sqrt(
                    ABDKMath64x64.divu(targetPower, 1000)
                )
            )
        );
    }
}
