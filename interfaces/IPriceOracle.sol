// SPDX-License-Identifier: MIT
pragma solidity ^0.6.5;

interface IPriceOracle {
    function currentPrice() external view returns (uint256 price);
    function setCurrentPrice(uint256 price) external;
    event CurrentPriceUpdated(uint256 price);
}
