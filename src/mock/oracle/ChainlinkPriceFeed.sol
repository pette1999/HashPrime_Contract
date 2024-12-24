// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV3Interface} from "src/oracles/AggregatorV3Interface.sol";

contract ChainlinkPriceFeed is AggregatorV3Interface {
    struct RoundData {
        uint80 id;
        int256 answer;
        uint256 timestamp;
    }

    string public description;
    uint8 public decimals;
    uint256 public version;
    uint80 public roundId;
    mapping(uint80 => RoundData) public rounds;

    constructor(string memory _description, uint8 _decimals) {
        description = _description;
        decimals = _decimals;
    }

    function updatePrice(int256 _answer) external {
        roundId++;
        rounds[roundId] = RoundData({
            id: roundId,
            answer: _answer,
            timestamp: block.timestamp
        });
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId_,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return _getRoundData(_roundId);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId_,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return _getRoundData(roundId);
    }

    function _getRoundData(
        uint80 _roundId
    )
        private
        view
        returns (
            uint80 roundId_,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        RoundData memory roundData = rounds[_roundId];
        roundId_ = roundData.id;
        answer = roundData.answer;
        startedAt = roundData.timestamp;
        updatedAt = roundData.timestamp;
        answeredInRound = roundData.id;
    }
}
