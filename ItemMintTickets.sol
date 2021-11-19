pragma solidity ^0.6.5;

import "./Tickets.sol";
import "./Items.sol";

contract ItemMintTickets is Tickets {

    Items items;

    event ItemMinted(address indexed owner, uint256 indexed item);

    function initialize(Items _items) public initializer {
        __AccessControl_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _enabled = true;
        items = _items;
    }

    function mintItem() public {
        consumeTicket(1);
        uint256 itemId = items.mint(msg.sender, uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender))));
        emit ItemMinted(msg.sender, itemId);
    }

    function mintItemN() public {
        consumeTicket(10);
        uint256[] memory itemIds = items.mintN(msg.sender, 11, uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender))));
        for(uint i = 0; i < itemIds.length; i++) {
            emit ItemMinted(msg.sender, itemIds[i]);
        }
    }
}