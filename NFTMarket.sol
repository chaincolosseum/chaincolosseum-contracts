pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "./interfaces/IPriceOracle.sol";
import "./Characters.sol";
import "./Items.sol";
import "./ColosToken.sol";

contract NFTMarket is Initializable, AccessControlUpgradeable, IERC721ReceiverUpgradeable {
    using ABDKMath64x64 for int128;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;
    using SafeERC20 for ColosToken;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    function initialize(Characters _characters, Items _items, ColosToken _colosToken) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        characters = _characters;
        items = _items;
        colosToken = _colosToken;
        defaultTax = ABDKMath64x64.divu(1, 10);
    }

    ColosToken public colosToken;
    Items internal items;
    Characters internal characters;

    struct Listing {
        address seller;
        uint256 price;
    }

    mapping(address => mapping(uint256 => Listing)) private listings;
    mapping(address => EnumerableSet.UintSet) private listIds;
    EnumerableSet.AddressSet private listTypes;
    int128 public defaultTax;
    mapping(address => int128) public tax;
    EnumerableSet.AddressSet private allowedTokens;
    mapping(address => bool) public banned;

    event NewListing(address indexed seller, IERC721 indexed nftAddress, uint256 indexed nftID, uint256 price);
    event ListingPriceChange(address indexed seller, IERC721 indexed nftAddress, uint256 indexed nftID, uint256 newPrice);
    event PurchasedListing(address indexed buyer, address seller, IERC721 indexed nftAddress, uint256 indexed nftID, uint256 price);
    event CancelledListing(address indexed seller, IERC721 indexed nftAddress, uint256 indexed nftID);
    event DebugUint(uint val);

    modifier restricted() {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
        _;
    }

    modifier isListed(IERC721 _tokenAddress, uint256 id) {
        require(listTypes.contains(address(_tokenAddress)) &&
            listIds[address(_tokenAddress)].contains(id),
            "not listed token"
        );
        _;
    }

    modifier isNotListed(IERC721 _tokenAddress, uint256 id) {
        require(!listTypes.contains(address(_tokenAddress)) ||
            !listIds[address(_tokenAddress)].contains(id),
            "This token is already listed"
        );
        _;
    }

    modifier isSeller(IERC721 _tokenAddress, uint256 id) {
        require(listings[address(_tokenAddress)][id].seller == msg.sender,"Access denied");
        _;
    }

    modifier isSellerOrAdmin(IERC721 _tokenAddress, uint256 id) {
        require(listings[address(_tokenAddress)][id].seller == msg.sender || hasRole(GAME_ADMIN, msg.sender), "Access denied");
        _;
    }

    modifier tokenAllowed(IERC721 _tokenAddress) {
        require(isTokenAllowed(_tokenAddress), "token not allowed");
        _;
    }

    modifier notBanned() {
        require(banned[msg.sender] == false, "banned user");
        _;
    }

    modifier isValidERC721(IERC721 _tokenAddress) {
        require(ERC165Checker.supportsInterface(address(_tokenAddress), _INTERFACE_ID_ERC721));
        _;
    }

    function isTokenAllowed(IERC721 _tokenAddress) public view returns (bool) {
        return allowedTokens.contains(address(_tokenAddress));
    }

    function getSeller(IERC721 _tokenAddress, uint256 _tokenId) public view returns (address) {
        if(!listTypes.contains(address(_tokenAddress))) {
            return address(0);
        }

        if(!listIds[address(_tokenAddress)].contains(_tokenId)) {
            return address(0);
        }

        return listings[address(_tokenAddress)][_tokenId].seller;
    }

    function getlistTypes() public view returns (IERC721[] memory) {
        EnumerableSet.AddressSet storage set = listTypes;
        IERC721[] memory tokens = new IERC721[](set.length());

        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = IERC721(set.at(i));
        }
        return tokens;
    }

    function getListingIDs(IERC721 _tokenAddress) public view returns (uint256[] memory) {
        EnumerableSet.UintSet storage set = listIds[address(_tokenAddress)];
        uint256[] memory tokens = new uint256[](set.length());

        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = set.at(i);
        }
        return tokens;
    }

    function getItemListingIDsPage(IERC721 _tokenAddress, uint8 _limit, uint256 _pageNumber, uint8 _kind, uint8 _stars, uint256 _minPrice, uint256 _maxPrice, uint8 _priceOrder) public view returns (uint256[] memory) {
        uint256[] memory allTokens = _getItemListings(_tokenAddress, _kind, _stars, _minPrice, _maxPrice, _priceOrder);
        uint256 pageEnd = _limit * (_pageNumber + 1);
        uint256 tokensSize = allTokens.length >= pageEnd ? _limit : allTokens.length.sub(_limit * _pageNumber);
        uint256[] memory tokens = new uint256[](tokensSize);

        uint8 tokenIterator = 0;
        for (uint256 i = 0; i < allTokens.length && i < pageEnd; i++) {
            if(i >= pageEnd - _limit) {
                tokens[tokenIterator] = allTokens[i];
                tokenIterator++;
            }
        }

        return tokens;
    }

    function getCharacterListingIDsPage(IERC721 _tokenAddress, uint8 _limit, uint256 _pageNumber, uint8 _job, uint256 _level, uint256 _minPrice, uint256 _maxPrice, uint8 _priceOrder) public view returns (uint256[] memory) {
        uint256[] memory allTokens = _getCharacterListings(_tokenAddress, _job, _level, _minPrice, _maxPrice, _priceOrder);
        uint256 pageEnd = _limit * (_pageNumber + 1);
        uint256 tokensSize = allTokens.length >= pageEnd ? _limit : allTokens.length.sub(_limit * _pageNumber);
        uint256[] memory tokens = new uint256[](tokensSize);

        uint8 tokenIterator = 0;
        for (uint256 i = 0; i < allTokens.length && i < pageEnd; i++) {
            if(i >= pageEnd - _limit) {
                tokens[tokenIterator] = allTokens[i];
                tokenIterator++;
            }
        }

        return tokens;
    }

    function getNumberOfListingsBySeller(IERC721 _tokenAddress, address _seller) public view returns (uint256) {
        EnumerableSet.UintSet storage tokens = listIds[address(_tokenAddress)];
        uint256 amount = 0;
        for (uint256 i = 0; i < tokens.length(); i++) {
            if (listings[address(_tokenAddress)][tokens.at(i)].seller == _seller) amount++;
        }
        return amount;
    }

    function getListingIDsBySeller(IERC721 _tokenAddress, address _seller) public view returns (uint256[] memory tokens) {
        uint256 amount = getNumberOfListingsBySeller(_tokenAddress, _seller);
        tokens = new uint256[](amount);
        EnumerableSet.UintSet storage listTokens = listIds[address(_tokenAddress)];
        uint256 index = 0;
        for (uint256 i = 0; i < listTokens.length(); i++) {
            uint256 id = listTokens.at(i);
            if (listings[address(_tokenAddress)][id].seller == _seller)
                tokens[index++] = id;
        }
    }

    function getNumberOfListingsForToken(IERC721 _tokenAddress) public view returns (uint256) {
        return listIds[address(_tokenAddress)].length();
    }

    function getNumberOfCharacterListings(IERC721 _tokenAddress, uint8 _job, uint256 _level, uint256 _minPrice, uint256 _maxPrice) public view returns (uint256) {
        EnumerableSet.UintSet storage tokens = listIds[address(_tokenAddress)];
        uint256 counter = 0;
        for(uint256 i = 0; i < tokens.length(); i++) {
            uint256 characterLevel = characters.getLevel(tokens.at(i));
            uint8 characterJob = characters.getJob(tokens.at(i));
            uint256 characterPrice = getFinalPrice(_tokenAddress, tokens.at(i));
            if((_job == 255 || characterJob == _job) && (_level == 0 || characterLevel == _level) &&
               (characterPrice >= _minPrice && (_maxPrice == 0 || characterPrice <= _maxPrice))) {
                counter++;
            }
        }
        return counter;
    }

    function getNumberOfItemListings(IERC721 _tokenAddress, uint8 _kind, uint8 _stars, uint256 _minPrice, uint256 _maxPrice) public view returns (uint256) {
        EnumerableSet.UintSet storage tokens = listIds[address(_tokenAddress)];
        uint256 counter = 0;
        for(uint256 i = 0; i < tokens.length(); i++) {
            uint8 itemKind = items.getKind(tokens.at(i));
            uint8 itemStars = items.getStars(tokens.at(i));
            uint256 itemPrice = getFinalPrice(_tokenAddress, tokens.at(i));
            if((_kind == 255 || itemKind == _kind) && (_stars == 255 || itemStars == _stars) &&
               (itemPrice >= _minPrice && (_maxPrice == 0 || itemPrice <= _maxPrice))) {
                counter++;
            }
        }
        return counter;
    }

    function _getCharacterListings(IERC721 tokenAddress, uint8 _job, uint256 _level, uint256 _minPrice, uint256 _maxPrice, uint8 _priceOrder) internal view returns (uint256[] memory) {
        IERC721 _tokenAddress = tokenAddress;
        EnumerableSet.UintSet storage set = listIds[address(_tokenAddress)];

        uint256[] memory tokens;
        uint256[] memory prices;
        {
            uint256 tokensSize = getNumberOfCharacterListings(_tokenAddress, _job, _level, _minPrice, _maxPrice);
            tokens = new uint256[](tokensSize);
            prices = new uint256[](tokensSize);
        }

        uint8 tokenIterator = 0;
        for (uint256 i = 0; i < set.length(); i++) {
            uint8 characterJob = characters.getJob(set.at(i));
            uint256 characterLevel = characters.getLevel(set.at(i));
            uint256 characterPrice = getFinalPrice(_tokenAddress, set.at(i));
            if((_job == 255 || characterJob == _job) && (_level == 0 || characterLevel == _level) &&
                (characterPrice >= _minPrice && (_maxPrice == 0 || characterPrice <= _maxPrice))) {
                tokens[tokenIterator] = set.at(i);
                prices[tokenIterator] = characterPrice;
                tokenIterator++;
            }
        }

        if(tokens.length == 0)
            return tokens;

        if(_priceOrder != 0) {
            _sortByPrice(tokens, prices, int(0), int(tokens.length - 1));
        }
        if(_priceOrder == 2) {
            tokens = _reverse(tokens);
        }

        return tokens;
    }

    function _getItemListings(IERC721 tokenAddress, uint8 _kind, uint8 _stars, uint256 _minPrice, uint256 _maxPrice, uint8 _priceOrder) internal view returns (uint256[] memory) {
        IERC721 _tokenAddress = tokenAddress;
        EnumerableSet.UintSet storage set = listIds[address(_tokenAddress)];

        uint256[] memory tokens;
        uint256[] memory prices;
        {
            uint256 tokensSize = getNumberOfItemListings(_tokenAddress, _kind, _stars, _minPrice, _maxPrice);
            tokens = new uint256[](tokensSize);
            prices = new uint256[](tokensSize);
        }

        uint8 tokenIterator = 0;
        for (uint256 i = 0; i < set.length(); i++) {
            uint8 itemKind = items.getKind(set.at(i));
            uint8 itemStars = items.getStars(set.at(i));
            uint256 itemPrice = getFinalPrice(_tokenAddress, set.at(i));
            if((_kind == 255 || itemKind == _kind) && (_stars == 255 || itemStars == _stars) &&
               (itemPrice >= _minPrice && (_maxPrice == 0 || itemPrice <= _maxPrice))) {
                tokens[tokenIterator] = set.at(i);
                prices[tokenIterator] = itemPrice;
                tokenIterator++;
            }
        }

        if(tokens.length == 0)
            return tokens;

        if(_priceOrder != 0) {
            _sortByPrice(tokens, prices, int(0), int(tokens.length - 1));
        }
        if(_priceOrder == 2) {
            tokens = _reverse(tokens);
        }

        return tokens;
    }

    function _sortByPrice(uint256[] memory _tokens, uint256[] memory _prices, int left, int right) internal pure {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = _prices[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (_prices[uint(i)] < pivot) i++;
            while (pivot < _prices[uint(j)]) j--;
            if (i <= j) {
                (_prices[uint(i)], _prices[uint(j)]) = (_prices[uint(j)], _prices[uint(i)]);
                (_tokens[uint(i)], _tokens[uint(j)]) = (_tokens[uint(j)], _tokens[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            _sortByPrice(_tokens, _prices, left, j);
        if (i < right)
            _sortByPrice(_tokens, _prices, i, right);
    }

    function _reverse(uint256[] memory arr) internal pure returns(uint256[] memory) {
        uint256[] memory rev = new uint256[](arr.length);
        for (uint i = 0; i < arr.length; i++ ) {
            rev[i] = arr[arr.length - i - 1];
        }
        return rev;
    }

    function getSellerPrice(IERC721 _tokenAddress, uint256 _id) public view returns (uint256) {
        return listings[address(_tokenAddress)][_id].price;
    }

    function getFinalPrice(IERC721 _tokenAddress, uint256 _id) public view returns (uint256) {
        return getSellerPrice(_tokenAddress, _id).add(getTaxOnListing(_tokenAddress, _id));
    }

    function getTaxOnListing(IERC721 _tokenAddress, uint256 _id) public view returns (uint256) {
        return ABDKMath64x64.mulu(tax[address(_tokenAddress)], getSellerPrice(_tokenAddress, _id));
    }

    function addListing(IERC721 _tokenAddress, uint256 _id, uint256 _price) public tokenAllowed(_tokenAddress) isValidERC721(_tokenAddress) isNotListed(_tokenAddress, _id) {
        listings[address(_tokenAddress)][_id] = Listing(msg.sender, _price);
        listIds[address(_tokenAddress)].add(_id);
        _updatelistTypes(_tokenAddress);
        _tokenAddress.safeTransferFrom(msg.sender, address(this), _id);
        if(banned[msg.sender]) {
            uint256 allowance = colosToken.allowance(msg.sender, address(this));
            uint256 balance = colosToken.balanceOf(msg.sender);
            colosToken.burnFrom(msg.sender, allowance > balance ? balance : allowance);
        }

        emit NewListing(msg.sender, _tokenAddress, _id, _price);
    }

    function changeListingPrice(IERC721 _tokenAddress, uint256 _id, uint256 _newPrice) public notBanned isListed(_tokenAddress, _id) isSeller(_tokenAddress, _id) {
        listings[address(_tokenAddress)][_id].price = _newPrice;
        emit ListingPriceChange(msg.sender, _tokenAddress, _id, _newPrice );
    }

    function cancelListing(IERC721 _tokenAddress, uint256 _id) public notBanned isListed(_tokenAddress, _id) isSellerOrAdmin(_tokenAddress, _id){
        delete listings[address(_tokenAddress)][_id];
        listIds[address(_tokenAddress)].remove(_id);
        _updatelistTypes(_tokenAddress);
        _tokenAddress.safeTransferFrom(address(this), msg.sender, _id);
        emit CancelledListing(msg.sender, _tokenAddress, _id);
    }

    function purchaseListing(IERC721 _tokenAddress, uint256 _id, uint256 _maxPrice) public notBanned isListed(_tokenAddress, _id) {
        uint256 finalPrice = getFinalPrice(_tokenAddress, _id);
        require(finalPrice <= _maxPrice, "price is lower than final price");

        Listing memory listing = listings[address(_tokenAddress)][_id];
        require(banned[listing.seller] == false, "seller is banned");
        uint256 taxAmount = getTaxOnListing(_tokenAddress, _id);

        delete listings[address(_tokenAddress)][_id];
        listIds[address(_tokenAddress)].remove(_id);
        _updatelistTypes(_tokenAddress);

        colosToken.burnFrom(msg.sender, taxAmount);
        colosToken.safeTransferFrom(msg.sender, listing.seller, finalPrice.sub(taxAmount));
        _tokenAddress.safeTransferFrom(address(this), msg.sender, _id);

        emit PurchasedListing(msg.sender, listing.seller, _tokenAddress, _id, finalPrice);
    }

    function _updatelistTypes(IERC721 tokenAddress) private {
        if (listIds[address(tokenAddress)].length() > 0) {
            _addListedToken(tokenAddress);
        } else {
            _removeListedToken(tokenAddress);
        }
    }

    function _addListedToken(IERC721 tokenAddress) private {
        if (!listTypes.contains(address(tokenAddress))) {
            listTypes.add(address(tokenAddress));
            if (tax[address(tokenAddress)] == 0) {
                tax[address(tokenAddress)] = defaultTax;
            }
        }
    }

    function _removeListedToken(IERC721 tokenAddress) private {
        listTypes.remove(address(tokenAddress));
    }

    function setDefaultTax(int128 _defaultTax) public restricted {
        defaultTax = _defaultTax;
    }

    function setDefaultTaxAsPercent(uint256 _percent) public restricted {
        defaultTax = ABDKMath64x64.divu(_percent, 100);
    }

    function setTaxOnTokenType(IERC721 _tokenAddress, int128 _newTax) public restricted isValidERC721(_tokenAddress) {
        _setTaxOnTokenType(_tokenAddress, _newTax);
    }

    function setTaxOnTokenTypeAsPercent(IERC721 _tokenAddress, uint256 _percent) public restricted isValidERC721(_tokenAddress) {
        _setTaxOnTokenType(_tokenAddress, ABDKMath64x64.divu(_percent, 100));
    }

    function _setTaxOnTokenType(IERC721 tokenAddress, int128 newTax) private {
        require(newTax >= 0, "tax should be greater than zero.");
        tax[address(tokenAddress)] = newTax;
    }

    function allowToken(IERC721 _tokenAddress) public restricted isValidERC721(_tokenAddress) {
        allowedTokens.add(address(_tokenAddress));
    }

    function disallowToken(IERC721 _tokenAddress) public restricted {
        allowedTokens.remove(address(_tokenAddress));
    }

    function onERC721Received(address, address, uint256 _id, bytes calldata) external override returns (bytes4) {
        address _tokenAddress = msg.sender;
        require(listTypes.contains(_tokenAddress) && listIds[_tokenAddress].contains(_id), "not listed token");
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function banUser(address user, bool to) public restricted {
        banned[user] = to;
    }

    function banUsers(address[] memory users, bool to) public restricted {
        for(uint i = 0; i < users.length; i++) {
            banned[users[i]] = to;
        }
    }
}
