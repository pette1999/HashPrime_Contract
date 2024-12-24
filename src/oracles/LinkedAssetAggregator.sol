// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./AggregatorV3Interface.sol";

contract LinkedAssetAggregator is AggregatorV3Interface {
    AggregatorV3Interface public exchangeRateFeed;
    AggregatorV3Interface public originPriceFeed;
    string public description;

    /**
     * Constructor accepts two addresses:
     * _exchangeRateFeedAddress - The Chainlink price feed address for the token
     * _originPriceFeed - The Chainlink price feed address for original Token
     */
    constructor(address _exchangeRateFeedAddress, address _originPriceFeed, string memory _description) {
        exchangeRateFeed = AggregatorV3Interface(_exchangeRateFeedAddress);
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
        (
            uint80 tokenRoundId,
            int256 exchangeRate,
            uint256 tokenStartedAt,
            uint256 tokenUpdatedAt,
            uint80 tokenAnsweredInRound
        ) = exchangeRateFeed.latestRoundData();

        (, int256 ethPrice,,,) = originPriceFeed.latestRoundData();

        uint256 scaledExchangeRate = uint256(exchangeRate) * 10 ** (18 - uint256(exchangeRateFeed.decimals()));
        uint256 scaledEthPrice = uint256(ethPrice) * 10 ** (18 - uint256(originPriceFeed.decimals()));

        int256 finalPrice = int256((scaledEthPrice * scaledExchangeRate) / 1e18);

        // 使用代币的 roundId 和时间戳作为输出
        return (tokenRoundId, finalPrice, tokenStartedAt, tokenUpdatedAt, tokenAnsweredInRound);
    }

    function version() public pure override returns (uint256) {
        return uint8(8);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
