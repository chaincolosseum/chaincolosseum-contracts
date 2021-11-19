// SPDX-License-Identifier: MIT
pragma solidity ^0.6.5;

interface IRandoms {
    function getRandomSeed(address user) external view returns (uint256 seed);
}
