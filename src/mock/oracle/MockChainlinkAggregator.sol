// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

contract MockChainlinkAggregator {
    int256 public price;
    uint256 public updatedAt;
    uint8 public _decimals;
    uint8 public roundId;

    event PriceUpdated(int256 newPrice, uint256 updatedAt);

    constructor(int256 _price, uint8 decimals_) {
        setPrice(_price, decimals_);
    }

    function setPrice(int256 _price, uint8 decimals_) public {
        price = _price;
        _decimals = decimals_;
        updatedAt = block.timestamp;
        roundId += 1;
        emit PriceUpdated(_price, updatedAt);
    }

    function latestRoundData() public view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, price, updatedAt, block.timestamp, 0);
    }

    function getUpdatedAt() public view returns (uint256) {
        return updatedAt;
    }

    function getRoundData() public view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, price, updatedAt, block.timestamp, 0);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}
