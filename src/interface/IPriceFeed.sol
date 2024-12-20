// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "src/HToken.sol";

/**
 * @title IPriceFeed
 * @notice Interface for the PriceFeed contract which manages and updates price information for multiple assets.
 */
interface IPriceFeed {
    /**
     * @notice Initializes the contract with a specified Comptroller address.
     * @param _comptroller The address of the Comptroller to associate with this PriceFeed.
     */
    function initialize(address _comptroller) external;

    /**
     * @notice Sets the address for the sequencer uptime feed which monitors network uptime.
     * @param _sequencerUptimeFeed The address of the sequencer uptime feed.
     */
    function setSequencerUptimeFeed(address _sequencerUptimeFeed) external;

    /**
     * @notice Sets the price and associated Chainlink feeds for a given asset.
     * @param hToken The HToken for which to set the underlying asset price.
     * @param _prices The price to set for the asset.
     * @param _nativeChainlinkFeed Address of the native Chainlink feed for this asset
     */
    function setPrice(HToken hToken, uint256 _prices, address _nativeChainlinkFeed) external;

    /**
     * @notice Sets the underlying price of an hToken.
     * @param token The token whose price is being set.
     * @param price The price to set for the underlying asset of the hToken.
     */
    function setUnderlyingPrice(address token, uint256 price) external;

    /**
     * @dev Sets the price for a given htoken.
     * @param priceFeed Address of the Price feed.
     */
    function setEthPrice(address priceFeed) external;

    /**
     * @notice Retrieves the chainlink feed address for a given token symbol.
     * @param symbol The symbol of the hToken's underlying token to fetch the feed for.
     * @return The AssetPriceInfo containing details about the feed.
     */
    function getFeed(string memory symbol) external view returns (AssetPriceInfo memory);

    /**
     * @notice Fetches the price of an asset as set in this contract.
     * @param _underlyingAsset The address of the underlying asset.
     * @return The price of the asset.
     */
    function assetPrices(address _underlyingAsset) external view returns (uint256);

    /**
     * @notice Fetches the current price of a token managed by this contract.
     * @param hToken The hToken whose price to fetch.
     * @return price The current price of the hToken's underlying asset.
     */
    function getPrice(HToken hToken) external view returns (uint256);

    /**
     * @notice Fetches the underlying price of a listed hToken asset.
     * @param hToken The hToken whose underlying price to fetch.
     * @return The price of the underlying asset.
     */
    function getUnderlyingPrice(HToken hToken) external view returns (uint256);

    // Events
    event PricePosted(address indexed asset, uint256 previousPriceMantissa, uint256 newPriceMantissa);
    event NewAdmin(address indexed oldAdmin, address indexed newAdmin);
    event FeedSet(address indexed feed, string symbol);
    event PriceUpdated(address indexed oracle, uint256 price);
    event NewAssetPriceInfo(string indexed symbol, uint256 price, uint8 decimals);

    event AssetPriceUpdated(address indexed token, address indexed priceFeed, string symbol, uint256 price);

    // Structs
    /**
     * @notice Struct to hold asset price information.
     */
    struct AssetPriceInfo {
        uint256 price;
        address nativeChainlinkFeed;
        uint8 decimals;
    }

    /**
     * @notice Struct to hold DEX pair information for price queries.
     */
    struct CrocPairInfo {
        address base;
        address quote;
        uint256 poolIdx;
    }
}
