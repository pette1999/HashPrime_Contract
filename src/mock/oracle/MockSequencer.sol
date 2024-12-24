// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

contract MockSequencer {
    int256 public price;
    uint256 public updatedAt;
    uint8 public decimals;
    uint8 public roundId;

    event PriceUpdated(int256 newPrice, uint256 updatedAt);

    constructor() {}

    function setPrice(int256 _price, uint8 _decimals) public {
        price = _price;
        decimals = _decimals;
        updatedAt = block.timestamp;
        roundId += 1;
        emit PriceUpdated(_price, updatedAt);
    }

    function latestRoundData() public view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, 0, updatedAt, block.timestamp - 3600, 0);
    }

    function getUpdatedAt() public view returns (uint256) {
        return updatedAt;
    }

    function getRoundData() public view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, price, block.timestamp - 3 minutes, block.timestamp, 0);
    }
}
