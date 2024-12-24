// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IPythFeed {
    struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint256 publishTime;
    }

    function getPrice(bytes32 priceFeedId_) external view returns (Price memory);
}
