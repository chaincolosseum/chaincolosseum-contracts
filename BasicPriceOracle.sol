// SPDX-License-Identifier: MIT
pragma solidity ^0.6.5;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IPriceOracle.sol";

contract BasicPriceOracle is IPriceOracle, Initializable, AccessControlUpgradeable {
    bytes32 public constant PRICE_ADMIN = keccak256("PRICE_ADMIN");

    bool private priceSet;
    uint256 private currentPriceNum;

    event CurrentPriceUpdated(uint256 currentPrice);

    function initialize() public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PRICE_ADMIN, _msgSender());
        priceSet = false;
        currentPriceNum = 0;
    }

    function currentPrice() external override view returns (uint256) {
        require(priceSet, "No pre-set price");
        return currentPriceNum;
    }

    function setCurrentPrice(uint256 _currentPriceNum) external override {
        require(hasRole(PRICE_ADMIN, _msgSender()), "Missing PRICE_ADMIN role");
        require(_currentPriceNum > 0, "The price should be greater than zero");
        currentPriceNum = _currentPriceNum;
        priceSet = true;
        emit CurrentPriceUpdated(_currentPriceNum);
    }
}
