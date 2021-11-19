// SPDX-License-Identifier: MIT
pragma solidity ^0.6.5;

import "./interfaces/IRandoms.sol";

contract Randoms is IRandoms {
    uint256 private seed;

    function getRandomSeed(address user) external view override returns (uint256) {
        return uint256(keccak256(abi.encodePacked(user, seed, block.timestamp)));
    }

    function setSeed(uint256 _seed) external {
        seed = _seed;
    }
}
