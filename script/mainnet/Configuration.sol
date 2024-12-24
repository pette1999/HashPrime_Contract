// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import {Script, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {HToken} from "src/HToken.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC20Mintable} from "src/mock/token/ERC20Mintable.sol";
import {Addresses} from "src/utils/Addresses.sol";
import {MockChainlinkOracle} from "src/mock/oracle/MockChainlinkOracle.sol";
import {FaucetTokenWithPermit} from "src/mock/token/FaucetToken.sol";
import {Comptroller, Unitroller, ComptrollerInterface} from "src/Comptroller.sol";
import {Rate} from "src/Rate.sol";
import {PriceOracle} from "src/oracles/PriceOracle.sol";
import {LinkedAssetAggregator} from "src/oracles/LinkedAssetAggregator.sol";
import {ChainlinkPriceFeed} from "src/mock/oracle/ChainlinkPriceFeed.sol";

contract Configuration is Test, Script, Addresses {
    using Strings for uint256;
    using stdJson for string;

    struct JumpRateModelConfiguration {
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 jumpMultiplierPerYear;
        uint256 kink;
    }

    struct RTokenConfiguration {
        address tokenAddress;
        address chainlinkPriceFeed;
        /// decimal
        uint256 decimal;
        /// price
        uint256 price;
        /// initialMintAmount
        uint256 initialMintAmount;
        /// collateralFactor
        uint256 collateralFactor;
        /// reserveFactor
        uint256 reserveFactor;
        /// seizeShare
        uint256 seizeShare;
        /// supplyCap
        uint256 supplyCap;
        /// borrowCap
        uint256 borrowCap;
        /// priceFeedName
        string priceFeedName;
        /// tokenAddressName
        string tokenAddressName;
        /// name
        string name;
        /// symbol
        string symbol;
        /// addressesString
        string addressesString;
        /// jrm
        JumpRateModelConfiguration jrm;
    }
    /// underlying token address

    struct EmissionConfig {
        uint256 supplyEmissionPerSec;
        uint256 borrowEmissionsPerSec;
        uint256 endTime;
        address emissionToken;
        string hToken;
        string owner;
        string symbol;
    }

    mapping(uint256 => RTokenConfiguration[]) public hTokenConfigurations;

    /// mapping of all emission configs per chainid
    mapping(uint256 => EmissionConfig[]) public emissions;

    /// @notice supply caps of all hTokens that were added to the market with this proposal
    uint256[] public supplyCaps;

    /// @notice borrow caps of all hTokens that were added to the market with this proposal
    uint256[] public borrowCaps;

    /// @notice list of all hTokens that were added to the market with this proposal
    HToken[] public hTokens;

    // RTokenConfiguration[] public configJson;
    EmissionConfig[] public decodedEmissions;

    // lending
    uint256 public constant liquidationIncentiveMantissa = 1.1 ether;
    uint256 public constant closeFactorMantissa = 0.5 ether;

    /// @notice initial hToken mint amount
    uint256 public constant initialExchangeRate = 1e18;
    // Scroll Chainlink
    uint256 public constant FRESH_CHECK = 60;
    uint256 public constant GRACE_PERIOD_TIME = 3600;

    address public constant ETH_PRICE_FEED = address(0);

    function setupConfiguration() public {
        setupAddresses();
        setupHtokenList();

        console.log("\n\n------------ LOAD STATS ------------");
        console.log("Loaded %d HToken configs", hTokenConfigurations[block.chainid].length);
        console.log("Loaded %d reward configs", emissions[block.chainid].length);
        console.log("\n\n");
    }

    function setupHtokenList() public {
        // USDT
        // Redstone: 0xfBB68fC1445F73cc3296fb6Cef316EdAC53967b6
        // API3: 0x4eadC6ee74b7Ceb09A4ad90a33eA2915fbefcf76
        // Pyth: ID 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b
        hTokenConfigurations[block.chainid].push(
            RTokenConfiguration({
                decimal: 6,
                price: 1e6,
                tokenAddress: address(0),
                chainlinkPriceFeed: address(0),
                initialMintAmount: 1,
                collateralFactor: 0.7e18,
                reserveFactor: 0.3e18,
                seizeShare: 0.03e18,
                supplyCap: 1000000000e6,
                borrowCap: 500000000e6,
                priceFeedName: "USDT_ORACLE",
                tokenAddressName: "USDT",
                name: "Tether USD",
                symbol: "tUSDT",
                addressesString: "USDT",
                jrm: JumpRateModelConfiguration({
                    baseRatePerYear: 0.041 ether,
                    multiplierPerYear: 0.025 ether,
                    jumpMultiplierPerYear: 4.2 ether,
                    kink: 0.8 ether
                })
            })
        );

        // USDC
        // Redstone: 0x2eE9A7d22482905e7bb5E0aD832Be0DdB4d5582f
        // API3: 0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f
        // Pyth: ID 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a
        hTokenConfigurations[block.chainid].push(
            RTokenConfiguration({
                decimal: 6,
                price: 1e6,
                tokenAddress: address(0),
                chainlinkPriceFeed: address(0),
                initialMintAmount: 1,
                collateralFactor: 0.7e18,
                reserveFactor: 0.3e18,
                seizeShare: 0.03e18,
                supplyCap: 1000000000e6,
                borrowCap: 500000000e6,
                priceFeedName: "USDC_ORACLE",
                tokenAddressName: "USDC",
                name: "USDC",
                symbol: "tUSDC",
                addressesString: "USDC",
                jrm: JumpRateModelConfiguration({
                    baseRatePerYear: 0.02 ether,
                    multiplierPerYear: 0.025 ether,
                    jumpMultiplierPerYear: 4.2 ether,
                    kink: 0.8 ether
                })
            })
        );

        // fastUSD
        // Redstone: 0xBf3bA2b090188B40eF83145Be0e9F30C6ca63689 deUSD Price Feed
        // API3:
        // Pyth:
        hTokenConfigurations[block.chainid].push(
            RTokenConfiguration({
                decimal: 18,
                price: 70000e18,
                tokenAddress: address(0),
                chainlinkPriceFeed: address(0),
                initialMintAmount: 1,
                collateralFactor: 0.7e18,
                reserveFactor: 0.3e18,
                seizeShare: 0.03e18,
                supplyCap: 1000000000e18,
                borrowCap: 500000000e18,
                priceFeedName: "fastUSD_ORACLE",
                tokenAddressName: "fastUSD",
                name: "fastUSD",
                symbol: "tfastUSD",
                addressesString: "fastUSD",
                jrm: JumpRateModelConfiguration({
                    baseRatePerYear: 0.05 ether,
                    multiplierPerYear: 0.025 ether,
                    jumpMultiplierPerYear: 4.2 ether,
                    kink: 0.8 ether
                })
            })
        );
    }

    function getRTokenConfigurations(uint256 chainId) public view returns (RTokenConfiguration[] memory) {
        RTokenConfiguration[] memory configs = new RTokenConfiguration[](hTokenConfigurations[chainId].length);

        unchecked {
            uint256 configLength = configs.length;
            for (uint256 i = 0; i < configLength; i++) {
                configs[i] = RTokenConfiguration({
                    tokenAddress: hTokenConfigurations[chainId][i].tokenAddress,
                    chainlinkPriceFeed: hTokenConfigurations[chainId][i].chainlinkPriceFeed,
                    price: hTokenConfigurations[chainId][i].price,
                    decimal: hTokenConfigurations[chainId][i].decimal,
                    initialMintAmount: hTokenConfigurations[chainId][i].initialMintAmount,
                    collateralFactor: hTokenConfigurations[chainId][i].collateralFactor,
                    reserveFactor: hTokenConfigurations[chainId][i].reserveFactor,
                    seizeShare: hTokenConfigurations[chainId][i].seizeShare,
                    supplyCap: hTokenConfigurations[chainId][i].supplyCap,
                    borrowCap: hTokenConfigurations[chainId][i].borrowCap,
                    addressesString: hTokenConfigurations[chainId][i].addressesString,
                    priceFeedName: hTokenConfigurations[chainId][i].priceFeedName,
                    tokenAddressName: hTokenConfigurations[chainId][i].tokenAddressName,
                    symbol: hTokenConfigurations[chainId][i].symbol,
                    name: hTokenConfigurations[chainId][i].name,
                    jrm: hTokenConfigurations[chainId][i].jrm
                });
            }
        }

        return configs;
    }
}
