// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {HErc20Delegate} from "src/HErc20Delegate.sol";
import {HErc20Delegator} from "src/HErc20Delegator.sol";
import {FaucetTokenWithPermit} from "src/mock/token/FaucetToken.sol";
import {MockChainlinkAggregator} from "src/mock/oracle/MockChainlinkAggregator.sol";
import {MockSequencer} from "src/mock/oracle/MockSequencer.sol";
import "src/Comptroller.sol";
import "src/irm/JumpRateModel.sol";

import {CompositeOracle} from "src/oracles/CompositeOracle.sol";

contract CompositeOracleTest is Test {
    Comptroller comptroller;
    CompositeOracle priceFeed;
    HErc20Delegator tErc20Delegator;
    HErc20Delegate hTokenImpl;
    InterestRateModel irModel;
    FaucetTokenWithPermit faucetToken;
    HToken hToken;
    MockChainlinkAggregator faucetTokenAggregator;
    MockChainlinkAggregator ethAggregator;
    MockSequencer mockSequencer;

    uint256 expectedDexPrice = 3843403442139134434898;

    address private admin;

    function setUp() public {
        admin = address(this);
        irModel = new JumpRateModel(0.02e18, 0.15e18, 3e18, 0.6e18);

        faucetTokenAggregator = new MockChainlinkAggregator(3801e8, 8);
        ethAggregator = new MockChainlinkAggregator(3800e18, 18);
        mockSequencer = new MockSequencer();

        comptroller = new Comptroller();

        hTokenImpl = new HErc20Delegate();

        faucetToken = new FaucetTokenWithPermit(1e18, "Testing", 8, "TEST");
        tErc20Delegator = new HErc20Delegator(
            address(faucetToken),
            comptroller,
            irModel,
            1e18, // Exchange rate is 1:1 for tests
            "Test hToken",
            "hTEST",
            8,
            payable(address(this)),
            address(hTokenImpl),
            ""
        );
        hToken = HToken(address(tErc20Delegator));

        ProxyAdmin priceFeedProxyAdmin = new ProxyAdmin(address(this));
        CompositeOracle priceFeedImpl = new CompositeOracle();
        TransparentUpgradeableProxy priceFeedProxy = new TransparentUpgradeableProxy(
            address(priceFeedImpl), address(priceFeedProxyAdmin), abi.encodeWithSignature("initialize()", "")
        );
        priceFeed = CompositeOracle(address(priceFeedProxy));

        priceFeed.setFreshCheck(86400);
        priceFeed.setGracePeriodTime(3600);
        priceFeed.setHTokenConfig(hToken, address(faucetToken), 8);

        vm.label(address(priceFeed), "PriceFeed");
    }

    function testChaninlinkOracle() public {
        vm.warp(block.timestamp + 1000000);

        uint256 gracePeriodTime = priceFeed.getGracePeriodTime();
        uint256 freshCheck = priceFeed.getFreshCheck();

        assertEq(freshCheck, 86400);
        assertEq(gracePeriodTime, 3600);

        address[] memory aggregators = new address[](1);
        aggregators[0] = address(faucetTokenAggregator);
        priceFeed.setOracle(hToken, aggregators);

        priceFeed.setSequencerUptimeFeed(address(mockSequencer));
        address currentPriceFeed = priceFeed.getAssetAggregators(hToken)[0];
        assertEq(address(faucetTokenAggregator), currentPriceFeed);

        uint256 price = priceFeed.getPrice(hToken);
        uint256 underlyingPrice = priceFeed.getUnderlyingPrice(hToken);

        assertEq(address(faucetTokenAggregator), currentPriceFeed);

        assertEq(price, 3801e18);
        assertEq(underlyingPrice, 3801e28);
    }

    function testUnauthorizedRevert() public {
        address unauthorizedAccount = vm.addr(123);

        vm.startPrank(unauthorizedAccount);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedAccount)
        );
        priceFeed.setSequencerUptimeFeed(address(mockSequencer));

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedAccount)
        );
        priceFeed.setFreshCheck(86400);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedAccount)
        );
        priceFeed.setGracePeriodTime(3600);

        vm.stopPrank();
    }

    function testOralcePriority() public {
        testChaninlinkOracle();

        vm.warp(block.timestamp + 2000000);

        uint256 chainlinkPrice = priceFeed.getPrice(hToken);
        uint256 chainlinkUnderlyingPrice = priceFeed.getUnderlyingPrice(hToken);

        // Get chainlink price
        assertEq(chainlinkPrice, 3801e18);
        assertEq(chainlinkUnderlyingPrice, 3801e28);
    }
}
