// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "src/HToken.sol";
import "src/oracles/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title IPriceFeed
 * @notice Interface for the PriceFeed contract which manages and updates price information for multiple assets.
 */
interface ICompositeOracle {
    struct HTokenConfig {
        ERC20 underlying;
        HToken hToken;
        uint8 decimals;
    }

    // Events
    event UpdateGracePeriodTime(uint256 oldGracePeriodTime, uint256 newGracePeriodTime);
    event UpdateFreshCheck(uint256 oldFreshCheck, uint256 newFreshCheck);
    event UpdateSequencerUptimeFeed(address indexed oldSequencerUptimeFeed, address indexed newSequencerUptimeFeed);
    event OracleSetup(address indexed hToken, uint256 feedsNum);
    event HTokenConfigUpdate(address indexed hToken, address indexed underlying);

    // Custom Errors
    error SequencerDown();
    error GracePeriodNotOver();
    error PriceNotFresh();
    error InvalidPrice();
    error NoPriceFeedAvailable();

    // Interface Functions for Setting Information
    function setSequencerUptimeFeed(address sequencerUptimeFeed) external;

    // Interface Functions for Getting Information
    function getPrice(HToken hToken) external view returns (uint256);
    function getUnderlyingPrice(HToken hToken) external view returns (uint256);

    function setGracePeriodTime(uint256 gracePeriodTime) external;
    function setFreshCheck(uint256 freshCheck) external;
    function getGracePeriodTime() external view returns (uint256);
    function getFreshCheck() external view returns (uint256);
    function getSequencerUptimeFeed() external view returns (address);
    function getAssetAggregators(HToken hToken) external view returns (address[] memory);
}
