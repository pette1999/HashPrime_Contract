// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PythAggregatorV3} from "src/oracles/lib/PythAggregatorV3.sol";
import "src/interface/ICompositeOracle.sol";
import "src/interface/IPythFeed.sol";

/**
 * @title PriceFeedStorage
 * @dev PriceFeedStorage Contract to hold state variables to ensure continuity across upgrades.
 */
/// @custom:oz-upgrades-from PriceOracleV1
contract CompositeOracle is OwnableUpgradeable, ICompositeOracle {
    // Chainlink state
    uint256 public freshCheck;
    uint256 public gracePeriodTime;
    mapping(address => address[]) public aggregators;
    // Asset specific oracle configurations
    mapping(address => HTokenConfig) public configs;

    mapping(address => bool) public l2Aggregators;
    AggregatorV3Interface public sequencerUptimeFeed;

    /**
     * @dev Constructor initializes the contract using OpenZeppelin's Initializable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract with the OpenZeppelin's Ownable for upgradeable contracts.
     */
    function initialize() external initializer {
        __Ownable_init(msg.sender);
    }

    // External functions related to price feeds
    function setSequencerUptimeFeed(address sequencerUptimeFeed_) external onlyOwner {
        address oldSequencerUptimeFeed = address(sequencerUptimeFeed);
        sequencerUptimeFeed = AggregatorV3Interface(sequencerUptimeFeed_);
        emit UpdateSequencerUptimeFeed(oldSequencerUptimeFeed, sequencerUptimeFeed_);
    }

    function setL2Aggregators(address aggregator_, bool flag) external onlyOwner {
        l2Aggregators[aggregator_] = flag;
    }

    function setGracePeriodTime(uint256 gracePeriodTime_) external onlyOwner {
        require(gracePeriodTime_ > 0, "grace period time must greater than 0");
        uint256 oldGracePeriodTime = gracePeriodTime;
        gracePeriodTime = gracePeriodTime_;
        emit UpdateGracePeriodTime(oldGracePeriodTime, gracePeriodTime_);
    }

    function setFreshCheck(uint256 freshCheck_) external onlyOwner {
        uint256 oldFreshCheck = freshCheck;
        freshCheck = freshCheck_;
        emit UpdateFreshCheck(oldFreshCheck, freshCheck_);
    }

    function getGracePeriodTime() external view override returns (uint256) {
        return gracePeriodTime;
    }

    function getFreshCheck() external view override returns (uint256) {
        return freshCheck;
    }

    function getSequencerUptimeFeed() external view override returns (address) {
        return address(sequencerUptimeFeed);
    }

    function getAssetAggregators(HToken hToken) external view override returns (address[] memory) {
        return aggregators[address(hToken)];
    }

    function setHTokenConfig(HToken hToken, address underlyingAddr, uint8 decimals) external onlyOwner {
        address hTokenAddr = address(hToken);

        configs[hTokenAddr] = HTokenConfig({underlying: ERC20(underlyingAddr), hToken: hToken, decimals: decimals});

        emit HTokenConfigUpdate(hTokenAddr, underlyingAddr);
    }

    function getUnderlying(HToken hToken) public view returns (ERC20 underlying) {
        return configs[address(hToken)].underlying;
    }

    function getRTokenConfig(HToken hToken) public view returns (HTokenConfig memory) {
        HTokenConfig memory data = configs[address(hToken)];
        return data;
    }

    function setOracle(HToken hToken, address[] memory aggregators_) public onlyOwner {
        require(aggregators_.length > 0, "No valid aggregator");
        address hTokenAddr = address(hToken);
        aggregators[hTokenAddr] = aggregators_;
        emit OracleSetup(hTokenAddr, aggregators_.length);
    }

    function getPrice(HToken hToken) public view override returns (uint256) {
        return getPriceCommon(hToken, false);
    }

    function getUnderlyingPrice(HToken hToken) public view override returns (uint256) {
        return getPriceCommon(hToken, true);
    }

    function getPriceCommon(HToken hToken, bool isUnderlying) internal view returns (uint256 price) {
        if (isUnderlying) {
            price = getUnderlyingScaledPrice(hToken);
            return price;
        } else {
            price = getStandardizedPrice(hToken);
            return price;
        }
    }

    function getStandardizedPrice(HToken hToken) internal view returns (uint256 price) {
        (, uint256 price_,) = getAggregatorData(hToken);
        price = price_;

        if (price == 0) {
            revert InvalidPrice();
        }
    }

    function getUnderlyingScaledPrice(HToken hToken) internal view returns (uint256 price) {
        ERC20 underlying = getUnderlying(hToken);
        uint256 decimals = address(underlying) == address(0) ? 18 : underlying.decimals();

        uint256 feedDecimals;

        (uint256 rawPrice,, uint256 decimals_) = getAggregatorData(hToken);
        feedDecimals = decimals_;
        price = scalePrice(rawPrice, feedDecimals, decimals);

        // Multiply by 10^36 and then divide by the square of the underlying token's decimals
        price = price * 10 ** (36 - 2 * decimals);
    }

    function scalePrice(uint256 price, uint256 fromDecimals, uint256 toDecimals) internal pure returns (uint256) {
        if (fromDecimals > toDecimals) {
            return price / 10 ** (fromDecimals - toDecimals);
        } else {
            return price * 10 ** (toDecimals - fromDecimals);
        }
    }

    function getAggregatorData(HToken hToken) internal view returns (uint256, uint256, uint256) {
        address[] memory aggregatorAddresses = aggregators[address(hToken)];
        require(aggregatorAddresses.length > 0, "No aggregators configured");

        for (uint256 i = 0; i < aggregatorAddresses.length; i++) {
            address aggregatorAddr = aggregatorAddresses[0];

            if (l2Aggregators[aggregatorAddr]) {
                chainlinkL2SequencerCheck();
            }

            AggregatorV3Interface aggregator = AggregatorV3Interface(aggregatorAddr);
            (bool success, bytes memory data) =
                aggregatorAddr.staticcall(abi.encodeWithSelector(aggregator.latestRoundData.selector));

            if (!success) {
                continue;
            }

            (, int256 answer,, uint256 updatedAt,) = abi.decode(data, (uint80, int256, uint256, uint256, uint80));
            if (answer <= 0 || (block.timestamp - updatedAt) >= freshCheck) {
                continue;
            }

            uint256 rawPrice = uint256(answer);
            uint256 decimals = uint256(aggregator.decimals());
            uint256 scaledPrice = scalePrice(rawPrice, decimals, 18);
            return (rawPrice, scaledPrice, decimals);
        }

        revert NoPriceFeedAvailable();
    }

    function chainlinkL2SequencerCheck() internal view {
        (, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();

        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert SequencerDown();
        }

        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= gracePeriodTime) {
            revert GracePeriodNotOver();
        }
    }
}
