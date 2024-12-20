// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import {Script, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FaucetToken} from "src/mock/token/FaucetToken.sol";
import {Configuration} from "./Configuration.sol";
import {MockChainlinkOracle} from "src/mock/oracle/MockChainlinkOracle.sol";
import {FaucetTokenWithPermit} from "src/mock/token/FaucetToken.sol";
import {Comptroller, Unitroller, ComptrollerInterface} from "src/Comptroller.sol";
import {Rate} from "src/Rate.sol";
import {PriceOracle} from "src/oracles/PriceOracle.sol";
import {HErc20Delegate} from "src/HErc20Delegate.sol";
import {ChainlinkPriceFeed} from "src/mock/oracle/ChainlinkPriceFeed.sol";
import {JumpRateModel, InterestRateModel} from "src/irm/JumpRateModel.sol";
import {HErc20Delegator} from "src/HErc20Delegator.sol";
import {LinkedAssetAggregator} from "src/oracles/LinkedAssetAggregator.sol";
import {HToken} from "src/HToken.sol";
import {HErc20} from "src/HErc20.sol";
// Oracle contracts
import {CompositeOracle} from "src/oracles/CompositeOracle.sol";

contract CoreScript is Test, Script, Configuration {
    using Strings for uint256;
    using stdJson for string;

    function deployCore(address _admin) public {
        Unitroller unitroller = new Unitroller();
        Comptroller comptroller = new Comptroller();

        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);
        unitroller._setPendingAdmin(_admin);
        Comptroller comptrollerProxy = Comptroller(address(unitroller));
        comptrollerProxy._setPauseGuardian(_admin);
        comptrollerProxy._setBorrowCapGuardian(_admin);
        comptrollerProxy._setSupplyCapGuardian(_admin);
        comptrollerProxy._setCloseFactor(closeFactorMantissa);
        comptrollerProxy._setLiquidationIncentive(liquidationIncentiveMantissa);

        // ---------------------------
        // RewardDistributor deployment start
        // ---------------------------
        // ProxyAdmin rewardDistributorProxyAdmin = new ProxyAdmin(_admin);
        // MultiRewardDistributor rewardDistributorImpl = new MultiRewardDistributor();
        // TransparentUpgradeableProxy rewardDistributor = new TransparentUpgradeableProxy(
        //     address(rewardDistributorImpl),
        //     address(rewardDistributorProxyAdmin),
        //     abi.encodeWithSignature("initialize(address,address)", address(unitroller), _admin)
        // );
        // MultiRewardDistributor rewardDistributorProxy = MultiRewardDistributor(address(rewardDistributor));
        // rewardDistributorProxyAdmin.transferOwnership(_admin);
        // ---------------------------
        // RewardDistributor deployment end
        // ---------------------------

        // ---------------------------
        // PriceFeed deployment start
        // ---------------------------
        ProxyAdmin priceFeedProxyAdmin = new ProxyAdmin(_admin);
        CompositeOracle priceFeedImpl = new CompositeOracle();
        TransparentUpgradeableProxy priceFeedProxy = new TransparentUpgradeableProxy(
            address(priceFeedImpl), address(priceFeedProxyAdmin), abi.encodeWithSignature("initialize()", "")
        );
        CompositeOracle priceFeed = CompositeOracle(address(priceFeedProxy));
        priceFeed.setFreshCheck(FRESH_CHECK);
        // priceFeed.setGracePeriodTime(GRACE_PERIOD_TIME);
        // priceFeed.setSequencerUptimeFeed(SEQUENCER_UPTIME_FEED);
        // ---------------------------
        // PriceFeed deployment end
        // ---------------------------

        HErc20Delegate tErc20Delegate = new HErc20Delegate();
        // comptrollerProxy._setRewardDistributor(MultiRewardDistributor(address(0)));
        comptrollerProxy._setPriceOracle(PriceOracle(address(priceFeed)));

        addAddress("RTOKEN_IMPLEMENTATION", address(tErc20Delegate), block.chainid, true);
        addAddress("UNITROLLER", address(unitroller), block.chainid, true);
        addAddress("COMPTROLLER", address(comptroller), block.chainid, true);
        // addAddress("MRD_PROXY", address(rewardDistributor), block.chainid, true);
        // addAddress("MRD_IMPL", address(rewardDistributorImpl), block.chainid, true);
        // addAddress("MRD_PROXY_ADMIN", address(rewardDistributorProxyAdmin), block.chainid, true);
        addAddress("PRICE_FEED_ORACLE", address(priceFeed), block.chainid, true);
    }

    /// @notice no contracts are deployed in this proposal
    function deployAsset(address deployer) public {
        Configuration.RTokenConfiguration[] memory hTokenConfigs = getRTokenConfigurations(block.chainid);
        address priceFeedAddr = getAddress("PRICE_FEED_ORACLE");
        CompositeOracle priceFeedOracle = CompositeOracle(priceFeedAddr);
        uint256 hTokenConfigsLength = hTokenConfigs.length;
        address[] memory aggregators = new address[](1);

        //// create all of the hTokens according to the configuration in Config.sol
        unchecked {
            for (uint256 i = 0; i < hTokenConfigsLength; i++) {
                Configuration.RTokenConfiguration memory config = hTokenConfigs[i];

                ERC20 currentToken = ERC20(config.tokenAddress);

                (JumpRateModel rateModel, HErc20Delegator market) = createErc20Market(
                    currentToken,
                    initialExchangeRate,
                    config.jrm.baseRatePerYear,
                    config.jrm.multiplierPerYear,
                    config.jrm.jumpMultiplierPerYear,
                    config.jrm.kink,
                    config.name,
                    config.symbol,
                    deployer
                );

                HToken hToken = HToken(address(market));
                priceFeedOracle.setHTokenConfig(hToken, address(currentToken), uint8(config.decimal));

                aggregators[0] = config.chainlinkPriceFeed;
                priceFeedOracle.setOracle(hToken, aggregators);

                hTokens.push(hToken);
                supplyCaps.push(config.supplyCap);
                borrowCaps.push(config.borrowCap);

                addAddress(config.tokenAddressName, address(currentToken), block.chainid, true);
                addAddress(config.symbol, address(market), block.chainid, true);
                addAddress(
                    string(abi.encodePacked("JUMP_RATE_IRM_", config.addressesString)),
                    address(rateModel),
                    block.chainid,
                    true
                );
            }
        }
    }

    /// helper function to validate supply and borrow caps
    function _validateCaps(Configuration.RTokenConfiguration memory config) private view {
        {
            if (config.supplyCap != 0 || config.borrowCap != 0) {
                uint8 decimals = ERC20(getAddress(config.tokenAddressName)).decimals();

                ///  defaults to false, dev can set to true to  these checks

                if (config.supplyCap != 0 && !vm.envOr("OVERRIDE_SUPPLY_CAP", false)) {
                    /// strip off all the decimals
                    uint256 adjustedSupplyCap = config.supplyCap / (10 ** decimals);
                    require(
                        // TODO - cap need to be ocnfirm
                        adjustedSupplyCap < 100000000 ether,
                        "supply cap suspiciously high, if this is the right supply cap, set OVERRIDE_SUPPLY_CAP environment variable to true"
                    );
                }

                if (config.borrowCap != 0 && !vm.envOr("OVERRIDE_BORROW_CAP", false)) {
                    uint256 adjustedBorrowCap = config.borrowCap / (10 ** decimals);
                    require(
                        // TODO - cap need to be ocnfirm
                        adjustedBorrowCap < 100000000 ether,
                        "borrow cap suspiciously high, if this is the right borrow cap, set OVERRIDE_BORROW_CAP environment variable to true"
                    );
                }
            }
        }
    }

    // TODO - Need to refine script
    function validate(address deployer) public {
        Configuration.RTokenConfiguration[] memory hTokenConfigs = getRTokenConfigurations(block.chainid);
        Comptroller comptroller = Comptroller(getAddress("UNITROLLER"));

        unchecked {
            for (uint256 i = 0; i < hTokenConfigs.length; i++) {
                Configuration.RTokenConfiguration memory config = hTokenConfigs[i];

                uint256 borrowCap = comptroller.borrowCaps(getAddress(config.symbol));
                uint256 supplyCap = comptroller.supplyCaps(getAddress(config.symbol));

                uint256 maxBorrowCap = (supplyCap * 10) / 9;

                /// validate borrow cap is always lte 90% of supply cap
                assertTrue(borrowCap <= maxBorrowCap, "borrow cap exceeds max borrow");

                /// hToken Assertions
                assertFalse(comptroller.mintGuardianPaused(getAddress(config.symbol)));
                /// minting allowed by guardian
                assertFalse(comptroller.borrowGuardianPaused(getAddress(config.symbol)));
                /// borrowing allowed by guardian
                assertEq(borrowCap, config.borrowCap);
                assertEq(supplyCap, config.supplyCap);

                /// assert hToken irModel is correct
                JumpRateModel jrm = JumpRateModel(getAddress(string(abi.encodePacked("JUMP_RATE_IRM_", config.symbol))));
                assertEq(address(HToken(getAddress(config.symbol)).interestRateModel()), address(jrm));

                HErc20 hToken = HErc20(getAddress(config.symbol));

                /// reserve factor and protocol seize share
                assertEq(hToken.protocolSeizeShareMantissa(), config.seizeShare);
                assertEq(hToken.reserveFactorMantissa(), config.reserveFactor);

                /// assert initial hToken balances are correct
                assertTrue(hToken.balanceOf(address(deployer)) > 0);
                /// deployer has some
                assertEq(hToken.balanceOf(address(0)), 1);
                /// address 0 has 1 wei of assets

                /// assert hToken admin is the temporal deployer
                assertEq(address(hToken.admin()), address(deployer));

                /// assert hToken comptroller is correct
                assertEq(address(hToken.comptroller()), getAddress("UNITROLLER"));

                /// assert hToken underlying is correct
                assertEq(address(hToken.underlying()), getAddress(config.tokenAddressName));

                /// assert hToken delegate is uniform across contracts
                assertEq(
                    address(HErc20Delegator(payable(address(hToken))).implementation()),
                    getAddress("RTOKEN_IMPLEMENTATION")
                );

                /// assert hToken initial exchange rate is correct
                assertEq(hToken.exchangeRateCurrent(), initialExchangeRate);

                /// assert hToken name and symbol are correct
                assertEq(hToken.name(), config.name);
                assertEq(hToken.symbol(), config.symbol);
                assertEq(hToken.decimals(), config.decimal);
            }
        }
    }

    function build() public {
        Configuration.RTokenConfiguration[] memory hTokenConfigs = getRTokenConfigurations(block.chainid);
        address priceFeedAddr = getAddress("PRICE_FEED_ORACLE");
        CompositeOracle priceFeedOracle = CompositeOracle(priceFeedAddr);
        Comptroller comptroller = Comptroller(getAddress("UNITROLLER"));

        console.log("Set supply caps HToken market");

        comptroller._setMarketSupplyCaps(hTokens, supplyCaps);
        comptroller._setMarketBorrowCaps(hTokens, borrowCaps);
        address[] memory aggregators = new address[](1);

        unchecked {
            for (uint256 i = 0; i < hTokenConfigs.length; i++) {
                Configuration.RTokenConfiguration memory config = hTokenConfigs[i];

                address hTokenAddress = getAddress(config.symbol);
                address tokenAddress = getAddress(config.tokenAddressName);

                HErc20Delegator currentRTokenProxy = HErc20Delegator(payable(hTokenAddress));
                HToken currentRToken = HToken(hTokenAddress);
                ERC20 underlyingToken = ERC20(tokenAddress);

                console.log("Set price feed for underlying address in HToken market");

                console.log("Set price feed address: ", config.chainlinkPriceFeed);

                priceFeedOracle.setHTokenConfig(currentRToken, address(underlyingToken), uint8(config.decimal));

                aggregators[0] = config.chainlinkPriceFeed;
                priceFeedOracle.setOracle(currentRToken, aggregators);

                console.log("Support HToken market in comptroller");
                comptroller._supportMarket(currentRToken);

                console.log("Approve underlying token to be spent by market");
                underlyingToken.approve(hTokenAddress, type(uint256).max);

                console.log("Initialize token market to prevent exploit");

                currentRTokenProxy.mint(config.initialMintAmount);
                currentRTokenProxy._setReserveFactor(config.reserveFactor);
                currentRTokenProxy._setProtocolSeizeShare(config.seizeShare);
                currentRTokenProxy.transfer(address(0), 1);
                console.log("Send 1 wei to address 0 to prevent a state where market has 0 hToken");

                console.log("Set Collateral Factor for HToken market in comptroller");
                comptroller._setCollateralFactor(currentRToken, config.collateralFactor);
            }
        }
    }

    function transferOwnership(address wallet) public {
        HToken rETH = HToken(getAddress("rETH"));
        HToken rUSDT = HToken(getAddress("rUSDT"));
        HToken rUSDC = HToken(getAddress("rUSDC"));
        HToken rwstETH = HToken(getAddress("rwstETH"));
        // HToken rweETH = HToken(getAddress("rweETH"));
        HToken rSTONE = HToken(getAddress("rSTONE"));

        Unitroller unitroller = Unitroller(getAddress("UNITROLLER"));
        Ownable priceFeedOracle = Ownable(getAddress("PRICE_FEED_ORACLE"));
        Comptroller comptrollerProxy = Comptroller(address(unitroller));

        // comptrollerProxy._setBorrowPaused(rweETH, false);
        comptrollerProxy._setBorrowPaused(rSTONE, true);

        unitroller._setPendingAdmin(wallet);
        priceFeedOracle.transferOwnership(wallet);

        comptrollerProxy._setPauseGuardian(wallet);
        comptrollerProxy._setBorrowCapGuardian(wallet);
        comptrollerProxy._setSupplyCapGuardian(wallet);

        rETH._setPendingAdmin(payable(wallet));
        rUSDT._setPendingAdmin(payable(wallet));
        rUSDC._setPendingAdmin(payable(wallet));
        // rweETH._setPendingAdmin(payable(wallet));
        rwstETH._setPendingAdmin(payable(wallet));
        rSTONE._setPendingAdmin(payable(wallet));
    }

    function createErc20Market(
        ERC20 underlyingAsset,
        uint256 _initialExchangeRateMantissa,
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink,
        string memory _name,
        string memory _symbol,
        address deployer
    ) public returns (JumpRateModel rateModel, HErc20Delegator market) {
        Comptroller comptrollerProxy = Comptroller(getAddress("UNITROLLER"));

        rateModel = new JumpRateModel(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink);

        market = new HErc20Delegator(
            address(underlyingAsset),
            ComptrollerInterface(comptrollerProxy),
            rateModel,
            _initialExchangeRateMantissa,
            _name,
            _symbol,
            underlyingAsset.decimals(),
            payable(deployer),
            getAddress("RTOKEN_IMPLEMENTATION"),
            ""
        );
    }
}
