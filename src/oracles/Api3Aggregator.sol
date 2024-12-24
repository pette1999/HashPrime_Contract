// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IProxy} from "src/interface/IProxy.sol";
import {AggregatorV3Interface} from "src/oracles/AggregatorV3Interface.sol";

contract Api3Aggregator is AggregatorV3Interface {
    IProxy public originPriceFeed;
    string public description;

    /**
     * Constructor accepts two addresses:
     * _originPriceFeed - The Chainlink price feed address for original Token
     */
    constructor(address _originPriceFeed, string memory _description) {
        originPriceFeed = IProxy(_originPriceFeed);
        description = _description;
    }

    /**
     * Implements the latestRoundData function from the AggregatorV3Interface.
     * Returns the token price relative to source token.
     */
    function latestRoundData()
        public
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (int224 value, uint32 timestamp) = originPriceFeed.read();
        uint256 updatedAt_ = uint256(timestamp);
        int256 scaledTokenPrice = int256(int224(uint224(value)));
        return (uint80(1), scaledTokenPrice, updatedAt_, block.timestamp - updatedAt_, uint80(0));
    }

    function version() public pure override returns (uint256) {
        return uint8(1);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
