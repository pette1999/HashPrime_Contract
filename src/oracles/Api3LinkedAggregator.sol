// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IProxy} from "src/interface/IProxy.sol";
import {AggregatorV3Interface} from "src/oracles/AggregatorV3Interface.sol";

contract Api3LinkedAggregator is AggregatorV3Interface {
    IProxy public exchangeRateFeed;
    AggregatorV3Interface public originPriceFeed;
    string public description;

    uint256 public freshCheck = 3600;

    error PriceNotFresh();

    /**
     * Constructor accepts two addresses:
     * _exchangeRateFeedAddress - The Chainlink price feed address for the token
     * _originPriceFeed - The Chainlink price feed address for original Token
     */
    constructor(address _exchangeRateFeedAddress, address _originPriceFeed, string memory _description) {
        exchangeRateFeed = IProxy(_exchangeRateFeedAddress);
        originPriceFeed = AggregatorV3Interface(_originPriceFeed);
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
        (int224 value, uint32 exchangeRateTimestamp) = exchangeRateFeed.read();
        uint256 duration = uint256(exchangeRateTimestamp) - block.timestamp;

        require(duration > freshCheck, "Not valid price");

        (uint80 tokenRoundId, int256 ethPrice,,, uint80 tokenAnsweredInRound) = originPriceFeed.latestRoundData();

        uint256 scaledExchangeRate = uint256(uint224(value));
        uint256 scaledEthPrice = uint256(ethPrice) * 10 ** (18 - uint256(originPriceFeed.decimals()));

        int256 finalPrice = int256((scaledEthPrice * scaledExchangeRate) / 1e18);

        return (
            tokenRoundId,
            finalPrice,
            uint256(exchangeRateTimestamp),
            uint256(exchangeRateTimestamp),
            tokenAnsweredInRound
        );
    }

    function version() public pure override returns (uint256) {
        return uint8(1);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
