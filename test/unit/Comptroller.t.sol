pragma solidity 0.8.23;

import "forge-std/Test.sol";

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockChainlinkAggregator} from "src/mock/oracle/MockChainlinkAggregator.sol";
import {HToken} from "src/HToken.sol";
import {SigUtils} from "test/helper/SigUtils.sol";
import {FaucetTokenWithPermit} from "src/mock/token/FaucetToken.sol";
import {MockSequencer} from "src/mock/oracle/MockSequencer.sol";
import {Comptroller} from "src/Comptroller.sol";
import {HErc20Immutable} from "src/mock/token/HErc20Immutable.sol";
import {SimplePriceOracle} from "src/mock/oracle/SimplePriceOracle.sol";
import {InterestRateModel} from "src/irm/InterestRateModel.sol";
import {ComptrollerErrorReporter} from "src/ErrorReporter.sol";
import {JumpRateModel} from "src/irm/JumpRateModel.sol";
import {CompositeOracle} from "src/oracles/CompositeOracle.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PriceOracle} from "src/oracles/PriceOracle.sol";

interface InstrumentedExternalEvents {
    event PricePosted(
        address asset, uint256 previousPriceMantissa, uint256 requestedPriceMantissa, uint256 newPriceMantissa
    );
    event NewCollateralFactor(HToken hToken, uint256 oldCollateralFactorMantissa, uint256 newCollateralFactorMantissa);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Mint(address minter, uint256 mintAmount, uint256 mintTokens);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
}

contract ComptrollerUnitTest is Test, InstrumentedExternalEvents, ComptrollerErrorReporter {
    Comptroller comptroller;
    CompositeOracle priceFeed;
    PriceOracle oracle;
    FaucetTokenWithPermit faucetToken;
    HErc20Immutable hToken;
    InterestRateModel irModel;
    SigUtils sigUtils;
    // MultiRewardDistributor distributor;
    address public constant proxyAdmin = address(1337);

    function setUp() public {
        comptroller = new Comptroller();
        MockSequencer mockSequencer = new MockSequencer();
        MockChainlinkAggregator faucetTokenAggregator = new MockChainlinkAggregator(1e18, 18);
        ProxyAdmin priceFeedProxyAdmin = new ProxyAdmin(address(this));
        CompositeOracle priceFeedImpl = new CompositeOracle();
        TransparentUpgradeableProxy priceFeedProxy = new TransparentUpgradeableProxy(
            address(priceFeedImpl), address(priceFeedProxyAdmin), abi.encodeWithSignature("initialize()", "")
        );
        priceFeed = CompositeOracle(address(priceFeedProxy));

        faucetToken = new FaucetTokenWithPermit(1e18, "Testing", 18, "TEST");
        irModel = new JumpRateModel(0.02e18, 0.15e18, 3e18, 0.6e18);

        hToken = new HErc20Immutable(
            address(faucetToken),
            comptroller,
            irModel,
            1e18, // Exchange rate is 1:1 for tests
            "Test hToken",
            "rTEST",
            8,
            payable(address(this))
        );

        // distributor = new MultiRewardDistributor();
        // bytes memory initdata =
        //     abi.encodeWithSignature("initialize(address,address)", address(comptroller), address(this));
        // TransparentUpgradeableProxy proxy =
        //     new TransparentUpgradeableProxy(address(distributor), address(proxyAdmin), initdata);
        /// wire proxy up
        // distributor = MultiRewardDistributor(address(proxy));
        oracle = PriceOracle(address(priceFeed));

        // comptroller._setRewardDistributor(distributor);
        comptroller._setPriceOracle(oracle);

        hToken._setReserveFactor(0.3e18);
        hToken._setProtocolSeizeShare(0.03e18);

        priceFeed.setFreshCheck(86400);
        priceFeed.setGracePeriodTime(3600);
        priceFeed.setSequencerUptimeFeed(address(mockSequencer));
        priceFeed.setHTokenConfig(hToken, address(faucetToken), 18);
        address[] memory aggregators = new address[](1);
        aggregators[0] = address(faucetTokenAggregator);
        priceFeed.setOracle(hToken, aggregators);

        sigUtils = new SigUtils(faucetToken.DOMAIN_SEPARATOR());

        vm.warp(block.timestamp + 1000000);
        comptroller._supportMarket(hToken);
        comptroller._setCloseFactor(0.5e18);
        comptroller._setCollateralFactor(hToken, 0.7e18);
    }

    function testWiring() public view {
        // Ensure things are wired correctly
        assertEq(comptroller.admin(), address(this));
        assertEq(priceFeed.owner(), address(this));
        assertEq(address(comptroller.oracle()), address(oracle));

        // Ensure we have 1 TEST token
        assertEq(faucetToken.balanceOf(address(this)), 1e18);

        // Ensure our market is listed
        (bool isListed,) = comptroller.markets(address(hToken));
        assertTrue(isListed);

        assertEq(oracle.getUnderlyingPrice(hToken), 1e18);
    }

    function testSettingCF(uint256 cfToSet) public {
        // Ensure our market is listed
        (, uint256 originalCF) = comptroller.markets(address(hToken));
        assertEq(originalCF, 0.7e18);

        assertEq(oracle.getUnderlyingPrice(hToken), 1e18);

        // If we set a CF > 90% things fail, so check that
        if (cfToSet > 0.9e18) {
            vm.expectEmit(true, true, true, true, address(comptroller));
            emit Failure(
                uint256(Error.INVALID_COLLATERAL_FACTOR), uint256(FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION), 0
            );
            comptroller._setCollateralFactor(hToken, cfToSet);
        } else {
            vm.expectEmit(true, true, true, true, address(comptroller));
            emit NewCollateralFactor(hToken, originalCF, cfToSet);

            uint256 setCollateralResult = comptroller._setCollateralFactor(hToken, cfToSet);
            assertEq(setCollateralResult, 0);

            (, uint256 collateralFactorUpdated) = comptroller.markets(address(hToken));
            assertEq(collateralFactorUpdated, cfToSet);
        }
    }

    function testBlakcList() public {
        testWiring();
        address blackListAccount1 = vm.addr(0x12345);
        faucetToken.allocateTo(blackListAccount1, 3000 ether);
        comptroller._setBlackList(blackListAccount1, true);

        vm.startPrank(blackListAccount1);
        bool paused = comptroller.mintGuardianPaused(address(hToken));
        assertFalse(paused);
        paused = comptroller.borrowGuardianPaused(address(hToken));
        assertFalse(paused);

        (bool isListed,) = comptroller.markets(address(hToken));
        assertTrue(isListed);

        faucetToken.approve(address(hToken), 1000 ether);
        uint256 err = hToken.mint(1000 ether);
        assertGt(err, 0);

        vm.startPrank(address(this));
        comptroller._setBlackList(blackListAccount1, false);
        vm.stopPrank();

        vm.startPrank(blackListAccount1);
        err = hToken.mint(1000 ether);
        assertEq(err, 0);

        err = hToken.redeem(1 ether);
        assertEq(err, 0);

        err = hToken.borrow(1 ether);
        assertEq(err, 0);

        vm.startPrank(address(this));
        comptroller._setBlackList(blackListAccount1, true);
        vm.stopPrank();

        err = hToken.redeem(1 ether);
        assertGt(err, 0);

        err = hToken.borrow(1 ether);
        assertGt(err, 0);
    }

    function testRedemptionPaused() public {
        comptroller._setRedeemPaused(hToken, true);
        faucetToken.allocateTo(address(this), 3000 ether);
        faucetToken.approve(address(hToken), 1000 ether);

        uint256 err = hToken.mint(1000 ether);
        assertEq(err, 0);

        vm.expectRevert("redeem is paused");
        hToken.redeem(1000 ether);

        comptroller._setRedeemPaused(hToken, false);

        err = hToken.redeem(1000 ether);
        assertEq(err, 0);
    }

    function testProtocalProtectedAccount() public {
        comptroller._setRedeemPaused(hToken, true);
        address liquidator = vm.addr(0x12345);
        faucetToken.allocateTo(liquidator, 100 ether);
        faucetToken.allocateTo(address(this), 3000 ether);
        faucetToken.approve(address(hToken), 1000 ether);

        uint256 err = hToken.mint(1 ether);
        assertEq(err, 0);

        err = hToken.borrow(0.7 ether);
        assertEq(err, 0);

        comptroller._setCollateralFactor(hToken, 0.5 ether);

        err = hToken.accrueInterest();
        assertEq(err, 0);

        (,, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        assertEq(shortfall, 0.2 ether);

        comptroller.triggerLiquidation(true);

        bool liquidatable = comptroller.liquidatable();
        assertTrue(liquidatable);

        comptroller.updateLiquidateWhiteList(liquidator, true);

        bool isWhiteListLiquidator = comptroller.liquidatorWhiteList(liquidator);
        assertTrue(isWhiteListLiquidator);

        vm.startPrank(liquidator);
        faucetToken.approve(address(hToken), 100 ether);

        err = hToken.mint(1 ether);
        assertEq(err, 0);

        err = comptroller.liquidateBorrowAllowed(address(hToken), address(hToken), liquidator, address(this), 0.3 ether);
        assertEq(err, 1);
    }

    function testGlobalPaused() public {
        address blackListAccount1 = vm.addr(0x12345);
        faucetToken.allocateTo(blackListAccount1, 3000 ether);

        comptroller._setProtocalPaused();
        bool paused = comptroller.borrowGuardianPaused(address(hToken));
        assertTrue(paused);

        paused = comptroller.mintGuardianPaused(address(hToken));
        assertTrue(paused);

        paused = comptroller.redeemGuardianPaused(address(hToken));
        assertTrue(paused);

        paused = comptroller.transferGuardianPaused();
        assertTrue(paused);

        paused = comptroller.seizeGuardianPaused();
        assertTrue(paused);

        vm.startPrank(blackListAccount1);

        faucetToken.approve(address(hToken), 1000 ether);
        vm.expectRevert("mint is paused");
        hToken.mint(1 ether);

        vm.stopPrank();

        // vm.startPrank(address(this));
        // comptroller._setProtocalPaused();
        // vm.stopPrank();

        // vm.startPrank(blackListAccount1);
        // uint256 err = hToken.mint(100 ether);
        // assertEq(err, 0);

        // err = hToken.redeem(0.1 ether);
        // assertEq(err, 0);

        // err = hToken.borrow(0.1 ether);
        // assertEq(err, 0);

        // vm.stopPrank();

        // vm.startPrank(address(this));
        // comptroller._setProtocalPaused();
        // vm.stopPrank();

        vm.expectRevert("redeem is paused");
        hToken.redeem(0.1 ether);

        vm.expectRevert("borrow is paused");
        hToken.borrow(0.1 ether);
    }

    function testEnterAllMarkets() public {
        address blackListAccount1 = vm.addr(0x12345);
        faucetToken.allocateTo(blackListAccount1, 3000 ether);

        vm.startPrank(address(hToken));
        uint256[] memory assets = comptroller.enterAllMarkets(blackListAccount1);
        assertEq(assets.length, 1);

        vm.stopPrank();
        vm.startPrank(address(this));
        vm.expectRevert("Sender must be a HToken contract");
        comptroller.enterAllMarkets(blackListAccount1);
    }

    // function testRewards() public {
    //     assertEq(oracle.getUnderlyingPrice(hToken), 1e18);

    //     comptroller._setCollateralFactor(hToken, 0.5e18);

    //     (, uint256 cf) = comptroller.markets(address(hToken));
    //     assertEq(cf, 0.5e18);

    //     faucetToken.approve(address(hToken), 1e18);
    //     hToken.mint(1e18);

    //     assertEq(faucetToken.balanceOf(address(this)), 0);

    //     uint256 time = 1678430000;
    //     vm.warp(time);

    //     distributor._addEmissionConfig(hToken, address(this), address(faucetToken), 0.5e18, 0, time + 86400);
    //     faucetToken.allocateTo(address(distributor), 100000e18);
    //     comptroller.claimReward();

    //     vm.warp(time + 10);

    //     comptroller.claimReward();

    //     // Make sure we got 10 * 0.5 == 5 tokens
    //     assertEq(faucetToken.balanceOf(address(this)), 5e18);

    //     // Make sure claiming twice in the same block doesn't do anything
    //     comptroller.claimReward();
    //     assertEq(faucetToken.balanceOf(address(this)), 5e18);
    // }
}
